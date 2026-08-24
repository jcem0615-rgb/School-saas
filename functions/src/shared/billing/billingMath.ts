/**
 * Pure billing math, deliberately free of any Firestore/Admin SDK
 * dependency so it can be unit tested without the emulator (see
 * functions/test/shared/billing/billingMath.test.ts).
 */

/** Daily Charge = Active Students x rate-per-student-per-day. */
export function computeDailyCharge(activeStudentCount: number, ratePerStudent: number): number {
  if (activeStudentCount < 0) {
    throw new Error("activeStudentCount cannot be negative.");
  }
  if (ratePerStudent < 0) {
    throw new Error("ratePerStudent cannot be negative.");
  }
  // Round to 2 decimal places to avoid floating point drift accumulating
  // across a month of daily accruals.
  return Math.round(activeStudentCount * ratePerStudent * 100) / 100;
}

/** Monthly Charge = sum of each day's charge across the billing cycle. */
export function computeMonthlyCharge(dailyCharges: number[]): number {
  const total = dailyCharges.reduce((sum, charge) => sum + charge, 0);
  return Math.round(total * 100) / 100;
}

/**
 * Given the date an invoice became overdue and the school's configured
 * grace period, returns the date auto-suspension should occur.
 */
export function computeSuspensionDeadline(overdueSince: Date, gracePeriodDays: number): Date {
  const deadline = new Date(overdueSince);
  deadline.setDate(deadline.getDate() + gracePeriodDays);
  return deadline;
}

export function isPastSuspensionDeadline(overdueSince: Date, gracePeriodDays: number, now: Date): boolean {
  return now.getTime() >= computeSuspensionDeadline(overdueSince, gracePeriodDays).getTime();
}
