/**
 * Pure balance arithmetic, deliberately free of Firestore types. A
 * positive `balance` means the student owes the school; a payment
 * reduces it (can go negative, representing a credit/overpayment); a
 * refund increases it back.
 */
export function applyPayment(currentBalance: number, amount: number): number {
  if (amount <= 0) {
    throw new Error("Payment amount must be positive.");
  }
  return round2(currentBalance - amount);
}

export function applyRefund(currentBalance: number, refundAmount: number): number {
  if (refundAmount <= 0) {
    throw new Error("Refund amount must be positive.");
  }
  return round2(currentBalance + refundAmount);
}

/**
 * Charging a student increases what they owe.
 *
 * The mirror of applyPayment, and deliberately the only other thing that
 * moves a balance upward besides a refund. Before this existed the only
 * way to raise a balance was setStudentBalance -- typing a total by hand
 * -- which produced a figure with no itemisation behind it and no way for
 * a family to ask what it was for.
 */
export function applyAssessment(currentBalance: number, total: number): number {
  if (total <= 0) {
    throw new Error("An assessment must total more than zero.");
  }
  return round2(currentBalance + total);
}

/**
 * Reverses an assessment that should not have been made.
 *
 * Voiding rather than deleting: the balance moved when the assessment was
 * made, so a record that could simply disappear would leave a figure
 * nobody could account for. This puts the balance back and leaves both
 * the charge and its reversal on the student's record.
 */
export function reverseAssessment(currentBalance: number, total: number): number {
  if (total <= 0) {
    throw new Error("An assessment must total more than zero.");
  }
  return round2(currentBalance - total);
}

/** Formats a sequential number into a human-readable receipt number, e.g. RC-2026-000042. */
export function formatReceiptNumber(sequence: number, year: number): string {
  return `RC-${year}-${String(sequence).padStart(6, "0")}`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
