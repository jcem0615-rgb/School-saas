import {validateDiscounts} from "../../../src/shared/payments/discounts";

/**
 * The server's half of discounts.
 *
 * One invariant carries the weight: a school may waive up to the whole
 * of what it is charging and not a centavo more. Past that the charge
 * goes negative -- the school paying a family to enrol -- and the balance
 * arithmetic would carry it without complaint.
 */
describe("validateDiscounts", () => {
  const sibling = {
    kind: "sibling",
    label: "Sibling discount",
    amount: 2000,
    percentage: 10,
    appliesTo: "tuition",
  };

  it("accepts a discount inside the fees", () => {
    const {discounts, discountTotal} = validateDiscounts([sibling], 24300, "Grace Mendoza");
    expect(discountTotal).toBe(2000);
    expect(discounts[0].label).toBe("Sibling discount");
    expect(discounts[0].percentage).toBe(10);
    expect(discounts[0].appliesTo).toBe("tuition");
  });

  it("treats no discounts as none", () => {
    expect(validateDiscounts(undefined, 24300, "Grace").discountTotal).toBe(0);
    expect(validateDiscounts([], 24300, "Grace").discountTotal).toBe(0);
  });

  it("stamps the approver from the caller, never from the payload", () => {
    // A client that could name its own approver could grant a
    // scholarship in the director's name.
    const {discounts} = validateDiscounts(
      [{...sibling, ...({approvedByName: "The Director"} as object)}],
      24300,
      "Grace Mendoza"
    );
    expect(discounts[0].approvedByName).toBe("Grace Mendoza");
  });

  it("allows waiving the exact total -- a full scholarship is real", () => {
    expect(
      validateDiscounts([{...sibling, amount: 24300}], 24300, "Grace").discountTotal
    ).toBe(24300);
  });

  it("refuses giving away more than is charged", () => {
    expect(() =>
      validateDiscounts([{...sibling, amount: 30000}], 24300, "Grace")
    ).toThrow(/cannot charge less than nothing/);
  });

  it("refuses two discounts that together exceed the fees", () => {
    // Each is fine on its own, which is exactly how this slips through
    // when only the individual lines are checked.
    expect(() =>
      validateDiscounts(
        [
          {...sibling, amount: 20000},
          {...sibling, label: "Early payment", amount: 5000},
        ],
        24300,
        "Grace"
      )
    ).toThrow(/cannot charge less than nothing/);
  });

  it("refuses a discount with no label", () => {
    expect(() =>
      validateDiscounts([{...sibling, label: "  "}], 24300, "Grace")
    ).toThrow(/has no label/);
  });

  it("refuses a zero or negative discount", () => {
    expect(() =>
      validateDiscounts([{...sibling, amount: 0}], 24300, "Grace")
    ).toThrow(/more than zero/);
  });

  it("refuses a rate outside 0 to 100", () => {
    expect(() =>
      validateDiscounts([{...sibling, percentage: 120}], 24300, "Grace")
    ).toThrow(/between 0 and 100 per cent/);
    expect(() =>
      validateDiscounts([{...sibling, percentage: -5}], 24300, "Grace")
    ).toThrow(/between 0 and 100 per cent/);
  });

  it("keeps a flat discount's null rate rather than inventing one", () => {
    const {discounts} = validateDiscounts(
      [{kind: "other", label: "Board grant", amount: 1500}],
      24300,
      "Grace"
    );
    expect(discounts[0].percentage).toBeNull();
    expect(discounts[0].appliesTo).toBeNull();
  });

  it("falls back to 'other' for a kind it does not recognise", () => {
    // A newer client, or a hand-written payload. Refusing the whole
    // assessment over a label would be worse than filing it under other.
    const {discounts} = validateDiscounts(
      [{...sibling, kind: "loyalty"}],
      24300,
      "Grace"
    );
    expect(discounts[0].kind).toBe("other");
  });

  it("refuses more lines than a school could mean", () => {
    const many = Array.from({length: 11}, () => ({...sibling, amount: 10}));
    expect(() => validateDiscounts(many, 24300, "Grace")).toThrow(/more than 10 discounts/);
  });

  it("refuses something that is not a list", () => {
    expect(() =>
      validateDiscounts("sibling" as unknown as undefined, 24300, "Grace")
    ).toThrow(/malformed/);
  });
});
