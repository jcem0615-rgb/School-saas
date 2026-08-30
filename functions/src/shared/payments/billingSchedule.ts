import {HttpsError} from "firebase-functions/v2/https";

/** One dated instalment, as it arrives from a client. */
export interface InstallmentData {
  label?: string;
  dueDate?: string;
  amount?: number;
}

/** One dated instalment, as it is stored. */
export interface StoredInstallment {
  label: string;
  dueDate: string;
  amount: number;
}

/**
 * A plan may have this many lines. Twelve monthly payments plus an
 * enrolment down payment is the longest real schedule; the cap is set
 * above that and below "somebody is pasting a spreadsheet in here".
 */
const MAX_INSTALLMENTS = 24;

const round2 = (value: number) => Math.round(value * 100) / 100;

/**
 * Validates a payment plan and returns it ready to store.
 *
 * The one invariant worth enforcing on the server: the plan must add up
 * to what is actually being charged. A plan that does not is worse than
 * no plan at all -- it either tells a family they have finished paying
 * when they have not, or chases them for money the school never charged
 * them. The client editor checks the same thing, and this checks it
 * again, because the client editor is not the only way to reach here.
 *
 * An empty plan is legal and means the whole amount is due immediately.
 * That is the honest reading of an ad-hoc charge -- a replacement ID is
 * not paid off over four months -- and it is what every assessment
 * written before this feature existed means.
 *
 * Dates are stored as the ISO strings they arrive as, deliberately. No
 * query filters on them: Firestore cannot filter on a field inside an
 * array element, so a Timestamp would buy nothing and cost a conversion
 * on both sides of every read.
 */
export function validateInstallments(
  raw: InstallmentData[] | undefined,
  chargedTotal: number
): StoredInstallment[] {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "The payment plan is malformed.");
  }
  if (raw.length === 0) return [];
  if (raw.length > MAX_INSTALLMENTS) {
    throw new HttpsError(
      "invalid-argument",
      `A payment plan cannot have more than ${MAX_INSTALLMENTS} instalments.`
    );
  }

  let planned = 0;
  const clean: StoredInstallment[] = raw.map((entry, index) => {
    const label = (entry?.label ?? "").trim();
    if (!label) {
      throw new HttpsError(
        "invalid-argument",
        `Instalment ${index + 1} has no label. A family reading the plan has ` +
          "to know which payment this is."
      );
    }

    const amount = Number(entry?.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError(
        "invalid-argument",
        `"${label}" must be more than zero. Remove the line instead.`
      );
    }

    const dueDate = new Date(entry?.dueDate ?? "");
    if (Number.isNaN(dueDate.getTime())) {
      throw new HttpsError("invalid-argument", `"${label}" has no valid due date.`);
    }

    planned += amount;
    return {label, dueDate: dueDate.toISOString(), amount: round2(amount)};
  });

  // A centavo of tolerance, because a school splitting 24,000 into three
  // gets 8,000.00 and one splitting 10,000 into three does not. Refusing
  // the second would make thirds unschedulable, which is absurd; letting
  // the difference grow past a centavo would let a plan drift from the
  // charge.
  if (Math.abs(round2(planned) - round2(chargedTotal)) > 0.01) {
    throw new HttpsError(
      "invalid-argument",
      `The payment plan adds up to ${round2(planned).toFixed(2)} but the ` +
        `assessment charges ${round2(chargedTotal).toFixed(2)}. A plan that ` +
        "does not match the charge either tells a family they have finished " +
        "paying when they have not, or chases them for money they were " +
        "never charged."
    );
  }

  return clean;
}

/**
 * What the plan says should have arrived by a given day.
 *
 * The server-side twin of BillingSchedule.amountDueBy in the app. Kept
 * here so anything running server-side -- a reminder job, an export --
 * asks the question the same way the screens do, rather than a second
 * implementation that rounds differently.
 */
export function amountDueBy(plan: StoredInstallment[], asOf: Date): number {
  const cutoff = Date.UTC(asOf.getUTCFullYear(), asOf.getUTCMonth(), asOf.getUTCDate());
  const due = plan
    .filter((line) => {
      const d = new Date(line.dueDate);
      return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) <= cutoff;
    })
    .reduce((sum, line) => sum + line.amount, 0);
  return round2(due);
}

/**
 * How far behind the plan a family is. Never negative: paying ahead is
 * not a debt owed the other way.
 */
export function overdueAmount(
  plan: StoredInstallment[],
  paid: number,
  asOf: Date
): number {
  const behind = amountDueBy(plan, asOf) - paid;
  return behind < 0.005 ? 0 : round2(behind);
}
