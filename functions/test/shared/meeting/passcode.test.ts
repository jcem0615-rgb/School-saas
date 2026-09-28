import {
  PASSCODE_LENGTH,
  displayPasscode,
  isPasscode,
  newPasscode,
  normalisePasscode,
  passcodeMatches,
} from "../../../src/shared/meeting/passcode";

/**
 * The code a teacher reads out before a lesson starts.
 *
 * Tested hardest on being read aloud badly, because that is what it is
 * for: a ten-year-old hearing eight characters over a bad connection
 * and typing them into a phone that capitalises the first letter on its
 * own.
 */
describe("the lesson passcode", () => {
  describe("what it is made of", () => {
    it("is eight characters, and a different eight each time", () => {
      const codes = new Set(Array.from({length: 500}, () => newPasscode()));

      expect(codes.size).toBe(500);
      for (const code of codes) {
        expect(code).toHaveLength(PASSCODE_LENGTH);
      }
    });

    it("never contains a character somebody could mishear", () => {
      // I and L for one, O for zero, and U so that eight random
      // characters cannot spell something a teacher has to read to a
      // class.
      const everything = Array.from({length: 2000}, () => newPasscode()).join("");

      expect(everything).not.toMatch(/[ILOU]/);
    });

    it("is long enough that guessing is not the way in", () => {
      // Thirty-two characters, eight of them: a thousand billion codes,
      // before the limit on attempts is reached at all.
      expect(Math.pow(32, PASSCODE_LENGTH)).toBeGreaterThan(1e12);
    });
  });

  describe("reading it back", () => {
    it("forgives the dash it was shown with", () => {
      expect(normalisePasscode("A1B2-C3D4")).toBe("A1B2C3D4");
      expect(displayPasscode("A1B2C3D4")).toBe("A1B2-C3D4");
    });

    it("forgives a keyboard that capitalised it", () => {
      expect(normalisePasscode("a1b2c3d4")).toBe("A1B2C3D4");
      expect(normalisePasscode("  A1B2 C3D4 ")).toBe("A1B2C3D4");
    });

    it("takes an eye for a one and an oh for a zero", () => {
      // A child who hears "eye" and types I is let in rather than told
      // they got it wrong.
      expect(normalisePasscode("I1L2O3")).toBe("111203");
      expect(passcodeMatches("IOIO2345", "1010" + "2345")).toBe(true);
    });

    it("is not a code when it is the wrong length or has a stray letter", () => {
      expect(isPasscode("A1B2C3D4")).toBe(true);
      expect(isPasscode("a1b2-c3d4")).toBe(true);
      expect(isPasscode("A1B2C3D")).toBe(false);
      expect(isPasscode("A1B2C3D45")).toBe(false);
      expect(isPasscode("A1B2C3DU")).toBe(false);
      expect(isPasscode("")).toBe(false);
      expect(isPasscode(null)).toBe(false);
      expect(isPasscode(12345678)).toBe(false);
    });

    it("recognises every code it makes", () => {
      for (let i = 0; i < 500; i++) {
        const code = newPasscode();
        expect(isPasscode(code)).toBe(true);
        expect(normalisePasscode(displayPasscode(code))).toBe(code);
      }
    });
  });

  describe("checking it", () => {
    it("lets the right code in and keeps the wrong one out", () => {
      expect(passcodeMatches("A1B2C3D4", "A1B2C3D4")).toBe(true);
      expect(passcodeMatches("a1b2-c3d4", "A1B2C3D4")).toBe(true);
      expect(passcodeMatches("A1B2C3D5", "A1B2C3D4")).toBe(false);
      expect(passcodeMatches("A1B2C3D", "A1B2C3D4")).toBe(false);
    });

    it("refuses everything when no code was set", () => {
      // A lesson without a passcode must not be a lesson where the
      // empty string is the passcode.
      for (const stored of [null, undefined, "", "   ", 0]) {
        expect(passcodeMatches("", stored)).toBe(false);
        expect(passcodeMatches("A1B2C3D4", stored)).toBe(false);
      }
    });

    it("refuses anything that is not a string", () => {
      expect(passcodeMatches(null, "A1B2C3D4")).toBe(false);
      expect(passcodeMatches(12345678, "A1B2C3D4")).toBe(false);
      expect(passcodeMatches({}, "A1B2C3D4")).toBe(false);
      expect(passcodeMatches(["A1B2C3D4"], "A1B2C3D4")).toBe(false);
    });

    it("does not say how much of a guess was right", () => {
      // Compared in constant time. The saving from stopping at the
      // first wrong character is microseconds; the cost is that a
      // patient caller learns the code one character at a time.
      const source = require("fs").readFileSync(
        require.resolve("../../../src/shared/meeting/passcode.ts"),
        "utf8"
      );

      expect(source).toContain("timingSafeEqual");
    });
  });
});
