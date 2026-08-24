import {applyPayment, applyRefund, formatReceiptNumber} from "../../../src/shared/payments/balanceMath";

describe("applyPayment", () => {
  it("reduces the balance by the payment amount", () => {
    expect(applyPayment(5000, 1500)).toBe(3500);
  });

  it("allows the balance to go negative (overpayment / credit)", () => {
    expect(applyPayment(1000, 1500)).toBe(-500);
  });

  it("rounds to 2 decimal places", () => {
    expect(applyPayment(100.1, 0.05)).toBeCloseTo(100.05, 2);
  });

  it("throws on a non-positive amount", () => {
    expect(() => applyPayment(1000, 0)).toThrow();
    expect(() => applyPayment(1000, -50)).toThrow();
  });
});

describe("applyRefund", () => {
  it("increases the balance by the refund amount", () => {
    expect(applyRefund(-500, 500)).toBe(0);
  });

  it("throws on a non-positive refund amount", () => {
    expect(() => applyRefund(0, 0)).toThrow();
  });
});

describe("formatReceiptNumber", () => {
  it("pads the sequence to 6 digits", () => {
    expect(formatReceiptNumber(42, 2026)).toBe("RC-2026-000042");
  });

  it("handles large sequences without truncation", () => {
    expect(formatReceiptNumber(1234567, 2026)).toBe("RC-2026-1234567");
  });
});
