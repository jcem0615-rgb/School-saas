import {normalizeSection, normalizeSections} from "../../../src/shared/sections";

/**
 * What counts as the same class.
 *
 * A section name is typed by hand on the student record, on the
 * teacher's assignment and on the timetable. Comparing them as raw
 * strings fails silently and always in the same direction: somebody is
 * not told something. This is the one place that decides otherwise, so
 * it is the one place worth pinning.
 */
describe("normalizeSection", () => {
  it("ignores case", () => {
    expect(normalizeSection("Grade 10 - Rizal")).toBe(normalizeSection("grade 10 - rizal"));
  });

  it("ignores leading and trailing space", () => {
    expect(normalizeSection("  Grade 10 - Rizal ")).toBe(normalizeSection("Grade 10 - Rizal"));
  });

  it("collapses runs of space, which is how a name gets typed twice", () => {
    expect(normalizeSection("Grade 10  -  Rizal")).toBe(normalizeSection("Grade 10 - Rizal"));
    expect(normalizeSection("Grade 10\t-\nRizal")).toBe(normalizeSection("Grade 10 - Rizal"));
  });

  it("does not make two different classes the same", () => {
    expect(normalizeSection("Grade 10 - Rizal")).not.toBe(normalizeSection("Grade 10 - Mabini"));
    expect(normalizeSection("Grade 1 - Rizal")).not.toBe(normalizeSection("Grade 10 - Rizal"));
  });

  it("reads a missing section as no section rather than throwing", () => {
    expect(normalizeSection(null)).toBe("");
    expect(normalizeSection(undefined)).toBe("");
    expect(normalizeSection("   ")).toBe("");
  });
});

describe("normalizeSections", () => {
  it("collapses names that differ only in how they were typed", () => {
    const set = normalizeSections(["Grade 10 - Rizal", "grade 10 - rizal ", "Grade 9 - Bonifacio"]);
    expect(set.size).toBe(2);
    expect(set.has(normalizeSection("Grade 10 - Rizal"))).toBe(true);
  });

  it("drops blanks, so an empty name matches nothing rather than everything", () => {
    expect(normalizeSections(["", "  ", "\t"]).size).toBe(0);
  });
});
