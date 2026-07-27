import {isValidEducationLevel} from "../../../src/shared/education/educationLevel";

describe("isValidEducationLevel", () => {
  it("accepts the three valid levels", () => {
    expect(isValidEducationLevel("elementary")).toBe(true);
    expect(isValidEducationLevel("high_school")).toBe(true);
    expect(isValidEducationLevel("college")).toBe(true);
  });

  it("rejects unknown strings", () => {
    expect(isValidEducationLevel("highschool")).toBe(false);
    expect(isValidEducationLevel("kindergarten")).toBe(false);
  });

  it("rejects non-string values", () => {
    expect(isValidEducationLevel(undefined)).toBe(false);
    expect(isValidEducationLevel(null)).toBe(false);
    expect(isValidEducationLevel(123)).toBe(false);
  });
});
