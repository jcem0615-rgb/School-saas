import {validateSubsidies} from "../../../src/shared/payments/subsidies";

/**
 * The server's half of ESC and voucher grants.
 *
 * Two invariants. A grant must cite the certificate it will be claimed
 * against -- without one the school cannot bill for it and the family has
 * simply been charged less. And the grants together cannot exceed what is
 * left after the school's own discounts, or the charge goes negative.
 */
describe("validateSubsidies", () => {
  const voucher = {
    programme: "shs_voucher",
    referenceNumber: "QVR-2026-0099142",
    amount: 6500,
  };

  it("accepts a grant inside what is chargeable", () => {
    const {subsidies, subsidyTotal} = validateSubsidies([voucher], 22000, "Joel");
    expect(subsidyTotal).toBe(6500);
    expect(subsidies[0].referenceNumber).toBe("QVR-2026-0099142");
    expect(subsidies[0].programme).toBe("shs_voucher");
  });

  it("treats no subsidies as none", () => {
    expect(validateSubsidies(undefined, 22000, "Joel").subsidyTotal).toBe(0);
    expect(validateSubsidies([], 22000, "Joel").subsidyTotal).toBe(0);
  });

  it("refuses a grant with no certificate number", () => {
    expect(() =>
      validateSubsidies([{...voucher, referenceNumber: "   "}], 22000, "Joel")
    ).toThrow(/certificate or voucher number/);
  });

  it("refuses the same certificate twice on one assessment", () => {
    // PEAC rejects the second claim, after the family has been charged
    // as though both were coming.
    expect(() =>
      validateSubsidies([voucher, voucher], 22000, "Joel")
    ).toThrow(/appears twice/);
  });

  it("allows the same number under two different programmes", () => {
    // Grantors number independently; a collision is coincidence.
    const {subsidyTotal} = validateSubsidies(
      [
        {...voucher, programme: "esc", amount: 5000},
        {...voucher, programme: "other", amount: 5000},
      ],
      22000,
      "Joel"
    );
    expect(subsidyTotal).toBe(10000);
  });

  it("matches certificate numbers regardless of case", () => {
    expect(() =>
      validateSubsidies(
        [voucher, {...voucher, referenceNumber: "qvr-2026-0099142"}],
        22000,
        "Joel"
      )
    ).toThrow(/appears twice/);
  });

  it("checks the ceiling against what is left after discounts", () => {
    // A student with a 2,000 sibling discount has 22,000 chargeable, not
    // 24,000. Checking against the gross would let the two together
    // exceed the fees.
    expect(() =>
      validateSubsidies([{...voucher, amount: 23000}], 22000, "Joel")
    ).toThrow(/the whole of what is left and no more/);
  });

  it("allows a grant covering exactly what is left", () => {
    expect(
      validateSubsidies([{...voucher, amount: 22000}], 22000, "Joel").subsidyTotal
    ).toBe(22000);
  });

  it("stamps the recorder from the caller, never from the payload", () => {
    const {subsidies} = validateSubsidies(
      [{...voucher, ...({recordedByName: "The Director"} as object)}],
      22000,
      "Joel Bautista"
    );
    expect(subsidies[0].recordedByName).toBe("Joel Bautista");
  });

  it("falls back to 'other' for an unrecognised programme", () => {
    const {subsidies} = validateSubsidies(
      [{...voucher, programme: "city_scholarship"}],
      22000,
      "Joel"
    );
    expect(subsidies[0].programme).toBe("other");
  });

  it("refuses a zero grant", () => {
    expect(() =>
      validateSubsidies([{...voucher, amount: 0}], 22000, "Joel")
    ).toThrow(/must be more than zero/);
  });

  it("refuses more lines than a student could hold", () => {
    const many = Array.from({length: 5}, (_, i) => ({
      ...voucher,
      referenceNumber: `QVR-${i}`,
      amount: 100,
    }));
    expect(() => validateSubsidies(many, 22000, "Joel")).toThrow(/more than 4 subsidies/);
  });

  it("refuses something that is not a list", () => {
    expect(() =>
      validateSubsidies("esc" as unknown as undefined, 22000, "Joel")
    ).toThrow(/malformed/);
  });
});
