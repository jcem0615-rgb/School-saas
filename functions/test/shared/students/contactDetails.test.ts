import {
  normalizeEmail,
  isValidEmail,
  validateContactDetails,
  ContactDetailsError,
} from "../../../src/shared/students/contactDetails";

describe("normalizeEmail", () => {
  it("keeps a multi-label domain", () => {
    // The case this exists for. Most Philippine school addresses are
    // *.edu.ph, and a single-label pattern rejects every one of them.
    expect(normalizeEmail("juan.delacruz@student.sanlorenzo.edu.ph"))
      .toBe("juan.delacruz@student.sanlorenzo.edu.ph");
  });

  it("lower-cases, so one person cannot become two accounts", () => {
    expect(normalizeEmail("Juan.DelaCruz@Gmail.com")).toBe("juan.delacruz@gmail.com");
  });

  it("trims what somebody pasted", () => {
    expect(normalizeEmail("  juan@gmail.com  ")).toBe("juan@gmail.com");
  });

  it("accepts the plus addressing a parent may well use", () => {
    expect(normalizeEmail("rosario+miguel@gmail.com")).toBe("rosario+miguel@gmail.com");
  });

  it("returns empty for anything that is not an address", () => {
    for (const bad of [
      "",
      "   ",
      "juan",
      "juan@",
      "@gmail.com",
      "juan@gmail",
      "juan gomez@gmail.com",
      "juan@@gmail.com",
      null,
      undefined,
      12345,
      {},
    ]) {
      expect(normalizeEmail(bad)).toBe("");
    }
  });

  it("isValidEmail agrees with it", () => {
    expect(isValidEmail("juan@school.edu.ph")).toBe(true);
    expect(isValidEmail("juan@school")).toBe(false);
  });
});

describe("validateContactDetails", () => {
  it("accepts a student with neither, which is most of them", () => {
    // A Grade 1 pupil has no email and no handset. A system that refuses
    // to register that child is a system whose registrar invents an
    // address, and then nobody can ever use it.
    expect(validateContactDetails({})).toEqual({email: null, phone: null});
    expect(validateContactDetails({email: "", phone: ""})).toEqual({email: null, phone: null});
    expect(validateContactDetails({email: "   ", phone: "  "})).toEqual({email: null, phone: null});
  });

  it("stores absent as null, not as an empty string", () => {
    // "Which students have no number on file?" is a list the office
    // genuinely wants before an emergency, and it cannot be built from a
    // column that mixes "" with null.
    const result = validateContactDetails({email: "juan@gmail.com"});
    expect(result.phone).toBeNull();
    expect(result.phone).not.toBe("");
  });

  it("keeps the number in the shape it was typed", () => {
    // The office reads this out loud to a parent. `+63 917 555 0100` is
    // legible; `639175550100` is a number somebody has to decode first.
    // Normalising is a matching-time concern, and it stays there.
    expect(validateContactDetails({phone: "+63 917 555 0100"}).phone)
      .toBe("+63 917 555 0100");
    expect(validateContactDetails({phone: "0917-555-0100"}).phone)
      .toBe("0917-555-0100");
  });

  it("accepts every shape a Philippine number gets written in", () => {
    for (const shape of [
      "09175550100",
      "+639175550100",
      "9175550100",
      "0917 555 0100",
      "(0917) 555-0100",
    ]) {
      expect(validateContactDetails({phone: shape}).phone).toBe(shape);
    }
  });

  it("refuses a number the password reset could never match", () => {
    // The whole point. A number stored in a shape normalizePhone cannot
    // read is a number that recovers nothing -- and that is discovered by
    // a family locked out of their account, on the day they need it.
    for (const bad of ["12", "abcdefg", "555-0100", "not a phone"]) {
      expect(() => validateContactDetails({phone: bad})).toThrow(ContactDetailsError);
    }
  });

  it("refuses an address with a typo, because it becomes the sign-in", () => {
    expect(() => validateContactDetails({email: "juan@gmailcom"}))
      .toThrow(ContactDetailsError);
    expect(() => validateContactDetails({email: "juan at gmail.com"}))
      .toThrow(ContactDetailsError);
  });

  it("says what was wrong with the value, not merely that it was wrong", () => {
    // A registrar looking at a form with eleven fields on it needs to be
    // told which one, and what a good one looks like.
    expect(() => validateContactDetails({phone: "12"}))
      .toThrow(/09171234567/);
    expect(() => validateContactDetails({email: "juan@gmailcom"}))
      .toThrow(/sign-in/);
  });

  it("normalises the email it returns but not the phone", () => {
    const result = validateContactDetails({
      email: "  Juan@Gmail.com ",
      phone: " 0917 555 0100 ",
    });
    expect(result.email).toBe("juan@gmail.com");
    expect(result.phone).toBe("0917 555 0100");
  });

  it("ignores a non-string, rather than storing its toString", () => {
    expect(validateContactDetails({email: 42, phone: {}})).toEqual({
      email: null,
      phone: null,
    });
  });
});
