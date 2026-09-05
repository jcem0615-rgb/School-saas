import {
  normaliseLinks,
  withLink,
  withoutLink,
  ParentLinkError,
} from "../../../src/shared/users/parentLinks";

/**
 * `linkedStudentIds` is a permission list wearing the clothes of a
 * profile field, so the arithmetic on it gets tested like one.
 */
describe("normaliseLinks", () => {
  it("passes a clean list through unchanged, order kept", () => {
    // Order is the order children were linked, which is the order the
    // office added them. Reordering would be harmless and confusing.
    expect(normaliseLinks(["stu_1", "stu_2", "stu_3"])).toEqual(["stu_1", "stu_2", "stu_3"]);
  });

  it("drops duplicates rather than growing the array on every re-link", () => {
    expect(normaliseLinks(["stu_1", "stu_1", "stu_2"])).toEqual(["stu_1", "stu_2"]);
  });

  it("drops blanks and non-strings, which would otherwise sit in an access list", () => {
    expect(normaliseLinks(["stu_1", "", "   ", null, 42, {}, "stu_2"]))
      .toEqual(["stu_1", "stu_2"]);
  });

  it("trims, so a pasted id with a trailing space is not a second child", () => {
    expect(normaliseLinks([" stu_1 ", "stu_1"])).toEqual(["stu_1"]);
  });

  it("treats a missing or malformed field as no access at all", () => {
    // The safe direction. An account whose field is missing should see
    // nothing, not everything.
    for (const raw of [undefined, null, "stu_1", 42, {}]) {
      expect(normaliseLinks(raw)).toEqual([]);
    }
  });
});

describe("withLink", () => {
  it("adds a child at the end", () => {
    expect(withLink(["stu_1"], "stu_2")).toEqual({
      links: ["stu_1", "stu_2"],
      changed: true,
    });
  });

  it("starts an account with no field at all", () => {
    expect(withLink(undefined, "stu_1")).toEqual({links: ["stu_1"], changed: true});
  });

  it("linking the same child twice changes nothing and says so", () => {
    // Two registrars working the same enrolment queue, or one clicking
    // twice. Neither is an error, and neither should write an audit line
    // for a link nobody made.
    expect(withLink(["stu_1", "stu_2"], "stu_1")).toEqual({
      links: ["stu_1", "stu_2"],
      changed: false,
    });
  });

  it("cleans the existing array on the way past", () => {
    // A record that picked up a duplicate before this function existed
    // gets tidied the next time it is touched, rather than being
    // preserved wrongly out of politeness.
    expect(withLink(["stu_1", "stu_1", ""], "stu_2")).toEqual({
      links: ["stu_1", "stu_2"],
      changed: true,
    });
  });

  it("refuses to link nothing", () => {
    expect(() => withLink(["stu_1"], "")).toThrow(ParentLinkError);
    expect(() => withLink(["stu_1"], "   ")).toThrow(ParentLinkError);
  });
});

describe("withoutLink", () => {
  it("removes the named child and leaves the rest", () => {
    expect(withoutLink(["stu_1", "stu_2", "stu_3"], "stu_2")).toEqual({
      links: ["stu_1", "stu_3"],
      changed: true,
    });
  });

  it("unlinking a child who was never linked changes nothing", () => {
    expect(withoutLink(["stu_1"], "stu_9")).toEqual({links: ["stu_1"], changed: false});
  });

  it("removing the last child leaves an empty array, not a missing field", () => {
    // A parent account with no children is a real state -- the family
    // left, or a wrong link was corrected before the right one was made.
    // It has to read correctly: `in []` is false, so the account simply
    // sees nothing. A deleted field would make the rules error instead.
    expect(withoutLink(["stu_1"], "stu_1")).toEqual({links: [], changed: true});
  });

  it("removes every copy when the array had picked up a duplicate", () => {
    expect(withoutLink(["stu_1", "stu_1", "stu_2"], "stu_1")).toEqual({
      links: ["stu_2"],
      changed: true,
    });
  });

  it("refuses to unlink nothing", () => {
    expect(() => withoutLink(["stu_1"], "")).toThrow(ParentLinkError);
  });
});

describe("linking and unlinking are inverses", () => {
  it("a link then an unlink returns the original access", () => {
    const start = ["stu_1", "stu_2"];
    const added = withLink(start, "stu_3").links;
    expect(withoutLink(added, "stu_3").links).toEqual(start);
  });

  it("an unlink then a re-link puts the child back, at the end", () => {
    // Not in the original position. That is fine and worth stating: the
    // array is a set with a stable display order, not a ranking.
    const start = ["stu_1", "stu_2", "stu_3"];
    const removed = withoutLink(start, "stu_1").links;
    expect(withLink(removed, "stu_1").links).toEqual(["stu_2", "stu_3", "stu_1"]);
  });
});
