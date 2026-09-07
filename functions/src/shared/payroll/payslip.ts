/**
 * What one employee is paid for one period.
 *
 * A port of `app/lib/features/payroll/domain/entities/payslip.dart`, and
 * the reason it is here rather than only there: until now the figures on
 * a payslip were worked out on the clerk's device and written straight
 * to Firestore. Everywhere else in this system that money moves, the
 * server recomputes it -- `recordPayment` re-reads a balance inside a
 * transaction rather than trusting the amount the client did the
 * arithmetic on. Payroll decides what a person is *paid* and had no
 * equivalent, which made a school's payslips exactly as trustworthy as
 * the browser tab they were issued from.
 *
 * Pure, and takes the timesheet rather than fetching one, so every
 * awkward case is a test: a month with no working days, an employee who
 * never scanned out, a salary above the top contribution bracket.
 *
 * ## What it does not do
 *
 * **Tardiness is reported, not deducted.** The timesheet knows a day was
 * late; it does not know by how long, because that needs the school's
 * own cutoff and the scan together. Deducting a made-up number of
 * minutes from somebody's pay is worse than printing "4 days late" and
 * letting the school decide.
 *
 * **No overtime.** Nothing in this system records authorised overtime,
 * and inferring it from a late scan-out would pay people for staying
 * behind to finish their own marking.
 */

import {
  ContributionScheme,
  CONTRIBUTION_LABELS,
  contributionOn,
  round2,
  tableFor,
} from "./contributions";
import {Timesheet} from "./timesheet";

export const PAY_BASES = ["monthly", "daily", "hourly"] as const;
export type PayBasis = (typeof PAY_BASES)[number];

export function payBasisFrom(value: unknown): PayBasis {
  return (PAY_BASES as readonly string[]).includes(String(value))
    ? (value as PayBasis)
    : "monthly";
}

/** What one employee is paid, and how. */
export interface Compensation {
  employeeUid: string;
  employeeName: string;
  basis: PayBasis;
  /** Pesos per month, per day or per hour, as `basis` says. */
  rate: number;
  /** Paid every period on top of the rate, and outside basic pay. */
  allowance: number;
  /** Whether an unworked day comes off the pay. */
  deductAbsences: boolean;
}

export interface PayslipLine {
  label: string;
  amount: number;
  /** Where the number came from, when it is not obvious. Printed under the label. */
  basis: string | null;
}

export interface Payslip {
  employeeUid: string;
  employeeName: string;
  periodFrom: string;
  periodTo: string;
  earnings: PayslipLine[];
  deductions: PayslipLine[];
  /** What contributions and 13th month are reckoned on. */
  basicPay: number;
  grossPay: number;
  totalDeductions: number;
  netPay: number;
  /** The school's own share. Never on the employee's copy; it is what the school remits. */
  employerContributions: number;
  daysWorked: number;
  daysAbsent: number;
  daysLate: number;
  daysMissingTimeOut: number;
}

/** Reads a compensation document, tolerating the fields it is missing. */
export function compensationFromDoc(
  employeeUid: string,
  data: Record<string, unknown> | undefined
): Compensation {
  const rate = Number(data?.rate);
  const allowance = Number(data?.allowance);
  return {
    employeeUid,
    employeeName: typeof data?.employeeName === "string" ? data.employeeName : "",
    basis: payBasisFrom(data?.basis),
    rate: Number.isFinite(rate) ? rate : 0,
    allowance: Number.isFinite(allowance) ? allowance : 0,
    // Defaults true, matching the entity: a school that has not said
    // otherwise deducts, which is the common arrangement.
    deductAbsences: data?.deductAbsences !== false,
  };
}

/**
 * A day's pay, for deducting absences and for daily-rate staff.
 *
 * The divisor is the school's working days in the period rather than a
 * fixed 22 or 26, because the period is what was actually worked and a
 * fixed divisor pays a short February differently from a long March for
 * no reason anybody can explain to staff.
 */
export function dailyRate(compensation: Compensation, workingDaysInPeriod: number): number {
  if (compensation.basis === "daily") return compensation.rate;
  if (workingDaysInPeriod <= 0) return 0;
  if (compensation.basis === "monthly") return round2(compensation.rate / workingDaysInPeriod);
  // Hourly staff have no meaningful day rate; absences are simply hours
  // not worked and never appear.
  return 0;
}

/**
 * The monthly figure the contribution tables are read with.
 *
 * Twenty-two working days, eight hours. Approximate on purpose and said
 * so: the alternative is asking every school to declare a divisor before
 * it can run payroll for one part-timer, and the bracket a part-timer
 * falls into is rarely close to a boundary.
 */
export function monthlyBasisFor(compensation: Compensation): number {
  switch (compensation.basis) {
  case "monthly":
    return compensation.rate;
  case "daily":
    return compensation.rate * 22;
  case "hourly":
    return compensation.rate * 22 * 8;
  }
}

const ABSENCES_LABEL = "Absences";

function peso(amount: number): string {
  return amount.toFixed(2);
}

/** Computes one payslip. */
export function computePayslip(input: {
  compensation: Compensation;
  timesheet: Timesheet;
  scheme: ContributionScheme;
  /**
   * The full monthly pay this employee is on, which is what the
   * contribution tables are indexed by -- not the pay for this period. A
   * semi-monthly payslip still deducts against the monthly bracket.
   */
  monthlyBasisForContributions: number;
  /**
   * True on the second cut-off of the month, when the contributions for
   * the whole month come off. Deducting the full amount twice would take
   * double from everybody on semi-monthly pay.
   */
  deductContributions?: boolean;
}): Payslip {
  const {compensation, timesheet, scheme, monthlyBasisForContributions} = input;
  const deductContributions = input.deductContributions !== false;

  const workingDays = timesheet.workingDays;
  const earnings: PayslipLine[] = [];
  const deductions: PayslipLine[] = [];

  let basic: number;
  switch (compensation.basis) {
  case "monthly":
    basic = round2(compensation.rate);
    earnings.push({label: "Basic pay", amount: basic, basis: "Monthly salary"});
    break;
  case "daily":
    basic = round2(compensation.rate * timesheet.daysWorked);
    earnings.push({
      label: "Basic pay",
      amount: basic,
      basis: `${timesheet.daysWorked} days at ${peso(compensation.rate)}`,
    });
    break;
  case "hourly": {
    const hours = timesheet.minutesWorked / 60;
    basic = round2(compensation.rate * hours);
    earnings.push({
      label: "Basic pay",
      amount: basic,
      basis: `${hours.toFixed(2)} hours at ${peso(compensation.rate)}`,
    });
    break;
  }
  }

  // Absences, for the bases where a day not worked is a day not paid.
  // Hourly staff are excluded by construction: their unworked hours were
  // never in the total to begin with, and deducting again would charge
  // them twice for the same absence.
  let absenceDeduction = 0;
  if (
    compensation.deductAbsences &&
    compensation.basis === "monthly" &&
    timesheet.daysAbsent > 0
  ) {
    const perDay = dailyRate(compensation, workingDays);
    absenceDeduction = round2(perDay * timesheet.daysAbsent);
    deductions.push({
      label: ABSENCES_LABEL,
      amount: absenceDeduction,
      basis: `${timesheet.daysAbsent} days at ${peso(perDay)}`,
    });
  }

  const basicAfterAbsences = round2(basic - absenceDeduction);

  if (compensation.allowance > 0) {
    earnings.push({
      label: "Allowance",
      amount: round2(compensation.allowance),
      basis: "Not subject to contributions",
    });
  }

  const gross = round2(basicAfterAbsences + compensation.allowance);

  let employerTotal = 0;
  if (deductContributions) {
    // The three agencies first: they come off before tax is reckoned,
    // which is what makes them worth doing in this order rather than any
    // other.
    for (const kind of ["sss", "philhealth", "pagibig"] as const) {
      const table = tableFor(scheme, kind);
      const amount = contributionOn(table, monthlyBasisForContributions);
      employerTotal += amount.employerShare;
      if (amount.employeeShare > 0) {
        deductions.push({
          label: CONTRIBUTION_LABELS[kind],
          amount: amount.employeeShare,
          basis: table.sourceLabel,
        });
      }
    }

    const agencyTotal = deductions
      .filter((d) => d.label !== ABSENCES_LABEL)
      .reduce((sum, d) => sum + d.amount, 0);

    // Tax is on what is left after the mandatory contributions, which is
    // the whole reason they are computed first.
    const taxable = round2(basicAfterAbsences - agencyTotal);
    const taxTable = tableFor(scheme, "withholding_tax");
    const tax = contributionOn(taxTable, taxable < 0 ? 0 : taxable);
    employerTotal += tax.employerShare;
    if (tax.employeeShare > 0) {
      deductions.push({
        label: CONTRIBUTION_LABELS.withholding_tax,
        amount: tax.employeeShare,
        basis: taxTable.sourceLabel,
      });
    }
  }

  const totalDeductions = round2(deductions.reduce((sum, d) => sum + d.amount, 0));

  return {
    employeeUid: compensation.employeeUid,
    employeeName: compensation.employeeName,
    periodFrom: timesheet.fromDate,
    periodTo: timesheet.toDate,
    earnings,
    deductions,
    basicPay: basicAfterAbsences,
    grossPay: gross,
    totalDeductions,
    // Never below zero. A deduction table that would take more than
    // somebody earned is a misconfiguration, and paying them a negative
    // amount is not a thing that can happen.
    netPay: round2(gross - totalDeductions < 0 ? 0 : gross - totalDeductions),
    employerContributions: round2(employerTotal),
    daysWorked: timesheet.daysWorked,
    daysAbsent: timesheet.daysAbsent,
    daysLate: timesheet.daysLate,
    daysMissingTimeOut: timesheet.daysMissingTimeOut,
  };
}

/** Whether the hours behind a payslip are known. */
export function hoursAreIncomplete(payslip: Payslip): boolean {
  return payslip.daysMissingTimeOut > 0;
}

/**
 * The 13th month pay, which is not a bonus and is not optional.
 *
 * PD 851: one twelfth of the basic salary earned in the calendar year.
 * Allowances are out of it and so is overtime, which is why a payslip
 * keeps basic pay apart from gross rather than only totalling.
 *
 * Takes what was actually earned rather than the monthly rate times
 * twelve, because somebody who joined in August is owed a twelfth of
 * what they earned, not a twelfth of a year they were not here for.
 */
export function thirteenthMonthPay(yearsPayslips: Iterable<Payslip>): number {
  let basic = 0;
  for (const payslip of yearsPayslips) basic += payslip.basicPay;
  return round2(basic / 12);
}
