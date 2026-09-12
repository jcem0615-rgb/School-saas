import {canonicalTerm, SCHOOL_TERMS} from "../../../src/shared/grading/terms";

describe("canonicalTerm", () => {
  it("leaves a canonical name alone", () => {
    for (const term of SCHOOL_TERMS) {
      expect(canonicalTerm(term)).toBe(term);
    }
  });

  it("resolves the shorthands people actually type", () => {
    expect(canonicalTerm("Q1")).toBe("1st Quarter");
    expect(canonicalTerm("q1")).toBe("1st Quarter");
    expect(canonicalTerm("1")).toBe("1st Quarter");
    expect(canonicalTerm("  q2  ")).toBe("2nd Quarter");
    expect(canonicalTerm("Quarter 4")).toBe("4th Quarter");
    expect(canonicalTerm("2ND QUARTER")).toBe("2nd Quarter");
  });

  it("keeps a name it does not recognise", () => {
    expect(canonicalTerm("Prelim")).toBe("Prelim");
    expect(canonicalTerm("Semester 1")).toBe("Semester 1");
  });

  it("leaves an empty term empty rather than guessing a quarter", () => {
    expect(canonicalTerm("")).toBe("");
    expect(canonicalTerm("   ")).toBe("");
  });

  it("agrees with the Dart list, which is the whole point of having one", () => {
    expect([...SCHOOL_TERMS]).toEqual([
      "1st Quarter",
      "2nd Quarter",
      "3rd Quarter",
      "4th Quarter",
    ]);
  });
});
