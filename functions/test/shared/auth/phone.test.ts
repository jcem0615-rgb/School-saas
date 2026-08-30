import {
  normalizePhone,
  resolvePhoneAccount,
  samePhone,
} from "../../../src/shared/auth/phone";

/**
 * Who a text message recovers.
 *
 * Too strict and a family is locked out by a space; too loose and one
 * family's number resets another family's password.
 */
describe("normalizePhone", () => {
  it("reads the three forms the same number gets written in", () => {
    expect(normalizePhone("+639175550100")).toBe("639175550100");
    expect(normalizePhone("09175550100")).toBe("639175550100");
    expect(normalizePhone("639175550100")).toBe("639175550100");
  });

  it("ignores the spaces, dashes and brackets people type", () => {
    expect(normalizePhone("0917 555 0100")).toBe("639175550100");
    expect(normalizePhone("(0917) 555-0100")).toBe("639175550100");
    expect(normalizePhone(" +63 917 555 0100 ")).toBe("639175550100");
  });

  it("accepts a bare mobile number with no prefix", () => {
    expect(normalizePhone("9175550100")).toBe("639175550100");
  });

  it("gives nothing back for what is not a phone number", () => {
    expect(normalizePhone("")).toBe("");
    expect(normalizePhone("   ")).toBe("");
    expect(normalizePhone("not a number")).toBe("");
    expect(normalizePhone("12")).toBe("");
    expect(normalizePhone(null)).toBe("");
    expect(normalizePhone(undefined)).toBe("");
    expect(normalizePhone(639175550100)).toBe("");
  });
});

describe("samePhone", () => {
  it("is true across formats", () => {
    expect(samePhone("0917 555 0100", "+639175550100")).toBe(true);
  });

  it("is false for different numbers", () => {
    expect(samePhone("09175550100", "09175550101")).toBe(false);
  });

  it("is false when either is unusable -- including both", () => {
    // Otherwise every account with a blank phone matches every other,
    // and a blank number recovers somebody's password.
    expect(samePhone("", "")).toBe(false);
    expect(samePhone("   ", "")).toBe(false);
    expect(samePhone("09175550100", "")).toBe(false);
  });
});

describe("resolvePhoneAccount", () => {
  const active = (uid: string, phone: string, extra = {}) => ({
    uid,
    phone,
    role: "parent",
    status: "active",
    isDeleted: false,
    ...extra,
  });

  it("recovers the one account that number belongs to", () => {
    const result = resolvePhoneAccount(
      [active("u1", "0917 555 0100"), active("u2", "0917 555 0199")],
      "+639175550100"
    );
    expect(result).toEqual({outcome: "matched", uid: "u1"});
  });

  it("finds nothing for a number nobody registered", () => {
    expect(resolvePhoneAccount([active("u1", "09175550100")], "09998887777"))
      .toEqual({outcome: "none"});
  });

  it("refuses when two accounts share a number", () => {
    // A parent who also works at the school, or a household with one
    // handset. Picking the first would reset a password the other
    // person did not ask to have reset.
    const result = resolvePhoneAccount(
      [active("u1", "09175550100"), active("u2", "+639175550100")],
      "09175550100"
    );
    expect(result).toEqual({outcome: "ambiguous", count: 2});
  });

  it("will not recover a suspended account", () => {
    expect(
      resolvePhoneAccount(
        [active("u1", "09175550100", {status: "suspended"})],
        "09175550100"
      )
    ).toEqual({outcome: "none"});
  });

  it("nor a deleted one", () => {
    expect(
      resolvePhoneAccount(
        [active("u1", "09175550100", {isDeleted: true})],
        "09175550100"
      )
    ).toEqual({outcome: "none"});
  });

  it("nor the platform owner, whatever the number says", () => {
    // A text message is not enough to take the account that can reach
    // every school on the platform.
    expect(
      resolvePhoneAccount(
        [active("u1", "09175550100", {role: "owner"})],
        "09175550100"
      )
    ).toEqual({outcome: "refused", reason: "owner"});
  });

  it("finds nothing when the number itself is unusable", () => {
    expect(resolvePhoneAccount([active("u1", "09175550100")], "hello"))
      .toEqual({outcome: "none"});
  });

  it("does not match an account with no phone on file", () => {
    expect(
      resolvePhoneAccount([{uid: "u1", role: "parent", status: "active"}], "09175550100")
    ).toEqual({outcome: "none"});
  });
});
