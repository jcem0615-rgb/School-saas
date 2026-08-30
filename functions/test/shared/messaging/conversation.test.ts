import {
  conversationId,
  isLinkedParent,
  isSendableMessage,
  MAX_MESSAGE_LENGTH,
  normalizeSection,
  previewOf,
  teachesSection,
} from "../../../src/shared/messaging/conversation";

describe("conversationId", () => {
  it("is the same for both people opening it", () => {
    // The property that stops two people messaging each other at the
    // same moment from ending up in two threads, each holding half the
    // conversation.
    expect(conversationId("t1", "p1", "s1")).toBe(conversationId("t1", "p1", "s1"));
  });

  it("is one thread per child, not per pair", () => {
    // A parent with two children taught by the same teacher gets two
    // threads, so "which child is this about" stays answerable.
    expect(conversationId("t1", "p1", "s1")).not.toBe(conversationId("t1", "p1", "s2"));
  });

  it("distinguishes the teacher and the parent", () => {
    expect(conversationId("t1", "p1", "s1")).not.toBe(conversationId("p1", "t1", "s1"));
  });
});

describe("isSendableMessage", () => {
  it("accepts ordinary text", () => {
    expect(isSendableMessage("Good morning po, about Miguel's absences")).toBe(true);
  });

  it("refuses an empty message", () => {
    // An empty bubble tells the other person nothing and still rings
    // their phone.
    expect(isSendableMessage("")).toBe(false);
    expect(isSendableMessage("   \n  ")).toBe(false);
  });

  it("refuses one long enough to be a problem", () => {
    expect(isSendableMessage("a".repeat(MAX_MESSAGE_LENGTH))).toBe(true);
    expect(isSendableMessage("a".repeat(MAX_MESSAGE_LENGTH + 1))).toBe(false);
  });
});

describe("previewOf", () => {
  it("collapses newlines so one row stays one row", () => {
    expect(previewOf("Good morning\n\nabout Miguel")).toBe("Good morning about Miguel");
  });

  it("truncates a long message", () => {
    const preview = previewOf("a".repeat(200), 20);
    expect(preview).toHaveLength(20);
    expect(preview.endsWith("…")).toBe(true);
  });

  it("leaves a short message alone", () => {
    expect(previewOf("Thank you po")).toBe("Thank you po");
  });
});

describe("teachesSection", () => {
  const assignments = [
    {teacherId: "t1", section: "Grade 10 - Rizal"},
    {teacherId: "t2", section: "BSCS 3-A"},
  ];

  it("is true for a section the teacher teaches", () => {
    expect(teachesSection(assignments, "t1", "Grade 10 - Rizal")).toBe(true);
  });

  it("is false for a section they do not", () => {
    expect(teachesSection(assignments, "t1", "BSCS 3-A")).toBe(false);
  });

  it("does not care about case or spacing", () => {
    // Section names are typed by hand in two places. Whether a parent
    // can reach their child's teacher should not turn on a stray space.
    expect(teachesSection(assignments, "t1", "  grade 10 -  rizal ")).toBe(true);
  });

  it("is false for an empty section rather than matching everything", () => {
    expect(teachesSection([{teacherId: "t1", section: ""}], "t1", "")).toBe(false);
  });

  it("is false when the teacher has no assignments at all", () => {
    expect(teachesSection([], "t1", "Grade 10 - Rizal")).toBe(false);
  });
});

describe("normalizeSection", () => {
  it("folds case and collapses runs of whitespace", () => {
    expect(normalizeSection("  Grade  10 -   RIZAL ")).toBe("grade 10 - rizal");
  });
});

describe("isLinkedParent", () => {
  it("is true when the child is on their list", () => {
    expect(isLinkedParent(["stu_1", "stu_2"], "stu_2")).toBe(true);
  });

  it("is false when it is not", () => {
    expect(isLinkedParent(["stu_1"], "stu_2")).toBe(false);
  });

  it("is false for a missing or malformed list rather than throwing", () => {
    // Fails closed: a parent document without the field must not become
    // a parent who can reach every child in the school.
    expect(isLinkedParent(undefined, "stu_1")).toBe(false);
    expect(isLinkedParent(null, "stu_1")).toBe(false);
    expect(isLinkedParent("stu_1", "stu_1")).toBe(false);
  });
});
