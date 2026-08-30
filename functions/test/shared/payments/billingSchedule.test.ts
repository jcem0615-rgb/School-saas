import {
  validateInstallments,
  amountDueBy,
  overdueAmount,
  StoredInstallment,
} from "../../../src/shared/payments/billingSchedule";

/**
 * The server's half of the payment plan.
 *
 * The client editor checks all of this too, and that is not a reason to
 * skip it here: a callable is reachable without going through that
 * screen, and the invariant being protected -- that the plan adds up to
 * what the family is actually charged -- is the one way this feature can
 * lie to somebody about money.
 */
describe("validateInstallments", () => {
  const quarterly = [
    {label: "Upon enrolment", dueDate: "2026-06-01T00:00:00.000Z", amount: 10000},
    {label: "August", dueDate: "2026-08-05T00:00:00.000Z", amount: 5000},
    {label: "October", dueDate: "2026-10-05T00:00:00.000Z", amount: 5000},
    {label: "December", dueDate: "2026-12-05T00:00:00.000Z", amount: 5000},
  ];

  it("accepts a plan that adds up to the charge", () => {
    const clean = validateInstallments(quarterly, 25000);
    expect(clean).toHaveLength(4);
    expect(clean[0].label).toBe("Upon enrolment");
    expect(clean[0].amount).toBe(10000);
  });

  it("treats no plan as legal -- the whole amount is due now", () => {
    expect(validateInstallments(undefined, 25000)).toEqual([]);
    expect(validateInstallments([], 25000)).toEqual([]);
  });

  it("refuses a plan that comes to less than the charge", () => {
    // The one that tells a family they have finished paying when they
    // have not.
    expect(() => validateInstallments(quarterly.slice(0, 3), 25000)).toThrow(
      /adds up to 20000.00 but the assessment charges 25000.00/
    );
  });

  it("refuses a plan that comes to more than the charge", () => {
    expect(() => validateInstallments(quarterly, 20000)).toThrow(/adds up to/);
  });

  it("allows a centavo of rounding, because thirds do not divide", () => {
    const thirds = [
      {label: "One", dueDate: "2026-06-01T00:00:00.000Z", amount: 3333.34},
      {label: "Two", dueDate: "2026-07-01T00:00:00.000Z", amount: 3333.33},
      {label: "Three", dueDate: "2026-08-01T00:00:00.000Z", amount: 3333.33},
    ];
    expect(validateInstallments(thirds, 10000)).toHaveLength(3);
  });

  it("refuses an instalment with no label", () => {
    // A family reading the plan has to know which payment they are being
    // asked for.
    expect(() =>
      validateInstallments([{label: "  ", dueDate: "2026-06-01", amount: 25000}], 25000)
    ).toThrow(/has no label/);
  });

  it("refuses a zero or negative instalment", () => {
    expect(() =>
      validateInstallments(
        [
          {label: "Down", dueDate: "2026-06-01", amount: 25000},
          {label: "Nothing", dueDate: "2026-07-01", amount: 0},
        ],
        25000
      )
    ).toThrow(/must be more than zero/);
  });

  it("refuses a due date that is not a date", () => {
    expect(() =>
      validateInstallments([{label: "August", dueDate: "next term", amount: 25000}], 25000)
    ).toThrow(/no valid due date/);
  });

  it("refuses a plan longer than a school could mean", () => {
    const many = Array.from({length: 25}, (_, i) => ({
      label: `Month ${i + 1}`,
      dueDate: "2026-06-01T00:00:00.000Z",
      amount: 100,
    }));
    expect(() => validateInstallments(many, 2500)).toThrow(/more than 24 instalments/);
  });

  it("refuses something that is not a list at all", () => {
    expect(() =>
      validateInstallments("June, August" as unknown as undefined, 25000)
    ).toThrow(/malformed/);
  });
});

describe("what should have arrived", () => {
  const plan: StoredInstallment[] = [
    {label: "Upon enrolment", dueDate: "2026-06-01T00:00:00.000Z", amount: 10000},
    {label: "August", dueDate: "2026-08-05T00:00:00.000Z", amount: 5000},
  ];

  it("counts a payment due today as due", () => {
    expect(amountDueBy(plan, new Date("2026-06-01T00:00:00.000Z"))).toBe(10000);
  });

  it("counts nothing before the first date", () => {
    expect(amountDueBy(plan, new Date("2026-05-31T23:59:59.000Z"))).toBe(0);
  });

  it("is never negative when a family pays ahead", () => {
    expect(overdueAmount(plan, 15000, new Date("2026-06-02T00:00:00.000Z"))).toBe(0);
  });

  it("reports the shortfall when they have not", () => {
    expect(overdueAmount(plan, 4000, new Date("2026-08-06T00:00:00.000Z"))).toBe(11000);
  });
});
