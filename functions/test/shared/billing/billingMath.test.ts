import {
  computeDailyCharge,
  computeMonthlyCharge,
  computeSuspensionDeadline,
  isPastSuspensionDeadline,
} from "../../../src/shared/billing/billingMath";

describe("computeDailyCharge", () => {
  it("multiplies active students by the rate", () => {
    expect(computeDailyCharge(500, 3)).toBe(1500);
  });

  it("returns 0 for a school with no active students", () => {
    expect(computeDailyCharge(0, 3)).toBe(0);
  });

  it("rounds to 2 decimal places", () => {
    expect(computeDailyCharge(333, 3.005)).toBeCloseTo(1000.67, 2);
  });

  it("throws on a negative student count", () => {
    expect(() => computeDailyCharge(-1, 3)).toThrow();
  });
});

describe("computeMonthlyCharge", () => {
  it("sums daily charges across a 30-day cycle", () => {
    const dailyCharges = new Array(30).fill(1500);
    expect(computeMonthlyCharge(dailyCharges)).toBe(45000);
  });

  it("handles a fluctuating enrollment across the month", () => {
    const dailyCharges = [1500, 1500, 1503, 1497];
    expect(computeMonthlyCharge(dailyCharges)).toBe(6000);
  });

  it("returns 0 for an empty billing cycle", () => {
    expect(computeMonthlyCharge([])).toBe(0);
  });
});

describe("suspension deadline", () => {
  const overdueSince = new Date("2026-07-01T00:00:00Z");

  it("computes the deadline as overdueSince + gracePeriodDays", () => {
    const deadline = computeSuspensionDeadline(overdueSince, 7);
    expect(deadline.toISOString().slice(0, 10)).toBe("2026-07-08");
  });

  it("is not past the deadline while within the grace period", () => {
    const now = new Date("2026-07-05T00:00:00Z");
    expect(isPastSuspensionDeadline(overdueSince, 7, now)).toBe(false);
  });

  it("is past the deadline once the grace period has elapsed", () => {
    const now = new Date("2026-07-09T00:00:00Z");
    expect(isPastSuspensionDeadline(overdueSince, 7, now)).toBe(true);
  });
});
