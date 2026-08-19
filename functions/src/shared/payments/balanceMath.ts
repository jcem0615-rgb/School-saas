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

/** Formats a sequential number into a human-readable receipt number, e.g. RC-2026-000042. */
export function formatReceiptNumber(sequence: number, year: number): string {
  return `RC-${year}-${String(sequence).padStart(6, "0")}`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
