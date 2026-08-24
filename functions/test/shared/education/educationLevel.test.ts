import {
  isValidEducationLevel,
  usesProgramCatalogue,
} from "../../../src/shared/education/educationLevel";

describe("isValidEducationLevel", () => {
  it("accepts the four valid divisions", () => {
    expect(isValidEducationLevel("elementary")).toBe(true);
    expect(isValidEducationLevel("high_school")).toBe(true);
    expect(isValidEducationLevel("senior_high")).toBe(true);
    expect(isValidEducationLevel("college")).toBe(true);
  });

  it("rejects unknown strings", () => {
    expect(isValidEducationLevel("highschool")).toBe(false);
    expect(isValidEducationLevel("seniorhigh")).toBe(false);
    expect(isValidEducationLevel("kindergarten")).toBe(false);
  });

  it("rejects non-string values", () => {
    expect(isValidEducationLevel(undefined)).toBe(false);
    expect(isValidEducationLevel(null)).toBe(false);
    expect(isValidEducationLevel(123)).toBe(false);
  });
});

describe("usesProgramCatalogue", () => {
  // Senior High picks a strand and College picks a degree program.
  // Elementary and Junior High pick neither -- their grade level and
  // section already say everything the record needs, so a programId on
  // one of those records is a mistake rather than extra information.
  it("is true only for the divisions that enrol in something", () => {
    expect(usesProgramCatalogue("senior_high")).toBe(true);
    expect(usesProgramCatalogue("college")).toBe(true);
    expect(usesProgramCatalogue("elementary")).toBe(false);
    expect(usesProgramCatalogue("high_school")).toBe(false);
  });
});
