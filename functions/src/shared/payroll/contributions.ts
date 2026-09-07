/**
 * The four things taken out of a Philippine payslip.
 *
 * A port of the Dart entity of the same shape, and the reason it is here
 * rather than only there: what an employee is paid must not be decided by
 * the client. `recordPayment` re-reads a student's balance inside a
 * transaction and recomputes it for exactly this reason; payroll decides
 * what a person is *paid*, and had no equivalent.
 *
 * Nothing is seeded. SSS, PhilHealth and Pag-IBIG rates move most years,
 * the withholding table moved with TRAIN and will move again, and the
 * numbers are fine-grained enough that a wrong one looks entirely
 * plausible on a payslip. The failure is not an out-of-date figure: it is
 * somebody under-deducted all year and handed a bill, or over-deducted
 * and quietly short every payday. The school types them from the circular
 * in front of it and confirms; until then no payslip is issued.
 */

export const CONTRIBUTION_KINDS = [
  "sss",
  "philhealth",
  "pagibig",
  "withholding_tax",
] as const;

export type ContributionKind = (typeof CONTRIBUTION_KINDS)[number];

export const CONTRIBUTION_LABELS: Record<ContributionKind, string> = {
  sss: "SSS",
  philhealth: "PhilHealth",
  pagibig: "Pag-IBIG",
  withholding_tax: "Withholding tax",
};

/**
 * One row of a table.
 *
 * One shape for all four, because all four are the same arithmetic: find
 * the bracket the amount falls in, take a fixed sum, add a percentage of
 * whatever is above the bracket's floor. SSS is fixed amounts per bracket
 * so the percentage is zero; PhilHealth and Pag-IBIG are percentages so
 * the fixed amount is; BIR withholding is the shape in full.
 */
export interface ContributionBracket {
  from: number;
  /** Null or undefined means no ceiling -- the top bracket. */
  to?: number | null;
  fixedAmount: number;
  percentOfExcess: number;
  employerFixedAmount: number;
  employerPercentOfExcess: number;
}

export interface ContributionTable {
  kind: ContributionKind;
  brackets: ContributionBracket[];
  /** "SSS Circular 2025-006", "RR 8-2018" -- printed beside the deduction. */
  sourceLabel: string | null;
}

export interface ContributionScheme {
  tables: ContributionTable[];
  confirmedBySchool: boolean;
  confirmedByName: string | null;
}

export interface ContributionAmount {
  employeeShare: number;
  employerShare: number;
}

/**
 * Two decimal places, rounding a half away from zero.
 *
 * Not `Math.round`, which rounds a half towards positive infinity and so
 * disagrees with the Dart implementation this is a port of on negative
 * halves. A payslip is one of the places where the two implementations
 * producing different centavos is a defect rather than a curiosity.
 */
export function round2(value: number): number {
  const scaled = value * 100;
  const rounded = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled);
  // `+ 0` so a rounded-to-nothing negative comes back as 0 rather than
  // -0, which prints as "-0.00".
  return rounded / 100 + 0;
}

function num(raw: unknown, fallback = 0): number {
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

export function isContributionKind(value: unknown): value is ContributionKind {
  return (CONTRIBUTION_KINDS as readonly string[]).includes(String(value));
}

/** Reads a scheme off its Firestore document, tolerating an absent one. */
export function schemeFromDoc(data: Record<string, unknown> | undefined): ContributionScheme {
  const rawTables = Array.isArray(data?.tables) ? (data!.tables as unknown[]) : [];
  const tables: ContributionTable[] = [];
  for (const raw of rawTables) {
    if (typeof raw !== "object" || raw === null) continue;
    const row = raw as Record<string, unknown>;
    if (!isContributionKind(row.kind)) continue;
    const rawBrackets = Array.isArray(row.brackets) ? (row.brackets as unknown[]) : [];
    tables.push({
      kind: row.kind,
      sourceLabel: typeof row.sourceLabel === "string" ? row.sourceLabel : null,
      brackets: rawBrackets
        .filter((b): b is Record<string, unknown> => typeof b === "object" && b !== null)
        .map((b) => ({
          from: num(b.from),
          to: b.to === null || b.to === undefined ? null : num(b.to),
          fixedAmount: num(b.fixedAmount),
          percentOfExcess: num(b.percentOfExcess),
          employerFixedAmount: num(b.employerFixedAmount),
          employerPercentOfExcess: num(b.employerPercentOfExcess),
        })),
    });
  }
  return {
    tables,
    confirmedBySchool: data?.confirmedBySchool === true,
    confirmedByName:
      typeof data?.confirmedByName === "string" ? data.confirmedByName : null,
  };
}

export function tableFor(scheme: ContributionScheme, kind: ContributionKind): ContributionTable {
  return (
    scheme.tables.find((t) => t.kind === kind) ??
    {kind, brackets: [], sourceLabel: null}
  );
}

/** Every agency the school has not filled in yet. */
export function unconfiguredKinds(scheme: ContributionScheme): ContributionKind[] {
  return CONTRIBUTION_KINDS.filter((kind) => tableFor(scheme, kind).brackets.length === 0);
}

/** Whether a payslip may be issued at all. */
export function canIssuePayslips(scheme: ContributionScheme): boolean {
  return scheme.confirmedBySchool && unconfiguredKinds(scheme).length === 0;
}

function covers(bracket: ContributionBracket, amount: number): boolean {
  return amount >= bracket.from &&
    (bracket.to === null || bracket.to === undefined || amount <= bracket.to);
}

/**
 * The bracket to use when the amount is above every ceiling.
 *
 * A table whose top has not kept up with a salary is a misconfiguration,
 * and deducting nothing from the highest earner in the school is a worse
 * way to find that out than deducting the maximum. Below the lowest
 * bracket is a different situation -- somebody earning under the table's
 * floor -- and nothing is due there.
 */
function topBracket(
  brackets: ContributionBracket[],
  amount: number
): ContributionBracket | null {
  if (brackets.length === 0) return null;
  const highest = brackets.reduce((a, b) => (a.from >= b.from ? a : b));
  return amount > highest.from ? highest : null;
}

/**
 * Reads one deduction out of a table.
 *
 * Zero for an empty table rather than an error: an empty table is a
 * school that has not configured that agency yet, and the refusal belongs
 * at `canIssuePayslips` so a half-configured school can still see what
 * the figures would be while it works through them.
 */
export function contributionOn(
  table: ContributionTable,
  monthlyPay: number
): ContributionAmount {
  if (table.brackets.length === 0) return {employeeShare: 0, employerShare: 0};

  const bracket =
    table.brackets.find((b) => covers(b, monthlyPay)) ??
    topBracket(table.brackets, monthlyPay);
  if (!bracket) return {employeeShare: 0, employerShare: 0};

  const excess = monthlyPay - bracket.from;
  const overFloor = excess < 0 ? 0 : excess;

  return {
    employeeShare: round2(
      bracket.fixedAmount + (overFloor * bracket.percentOfExcess) / 100
    ),
    employerShare: round2(
      bracket.employerFixedAmount + (overFloor * bracket.employerPercentOfExcess) / 100
    ),
  };
}
