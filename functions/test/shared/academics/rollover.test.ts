import {
  MAX_DECISIONS_PER_CALL,
  normaliseSchoolYear,
  studentUpdateFor,
  validateDecisions,
} from "../../../src/shared/academics/rollover";

/**
 * The server's half of the year-end rollover.
 *
 * The client draws up the plan and a registrar reads it, but this is
 * what actually holds: the screen is not the only way to reach the
 * callable, and the cost of a wrong row here is a child in the wrong
 * year for a school year -- found in June, by the child.
 */
describe("normaliseSchoolYear", () => {
  it("accepts the way schools write it", () => {
    expect(normaliseSchoolYear("2026-2027")).toBe("2026-2027");
    expect(normaliseSchoolYear(" 2026 / 2027 ")).toBe("2026-2027");
  });

  it("refuses anything that is not two consecutive years", () => {
    // This string is the document id that stops a rollover running
    // twice. "2026-27" and "SY 2026-2027" would be different ids for the
    // same year, and the second run would promote everybody again.
    expect(() => normaliseSchoolYear("2026-27")).toThrow(/not a school year/);
    expect(() => normaliseSchoolYear("SY 2026-2027")).toThrow(/not a school year/);
    expect(() => normaliseSchoolYear("")).toThrow(/not a school year/);
  });

  it("refuses a span that is not one year", () => {
    expect(() => normaliseSchoolYear("2026-2028")).toThrow(/spans 2 years/);
    expect(() => normaliseSchoolYear("2027-2026")).toThrow(/A school year runs/);
  });
});

describe("validateDecisions", () => {
  const promoted = {
    studentId: "stu_1",
    studentName: "Miguel Torres",
    recommended: "promoted",
    outcome: "promoted",
    fromGradeLevel: "Grade 9",
    fromSection: "Grade 9 - Rizal",
    toGradeLevel: "Grade 10",
    toSection: "Grade 10 - Rizal",
    generalAverage: 88,
    failedSubjects: [],
  };

  it("passes a well-formed promotion through", () => {
    const [decision] = validateDecisions([promoted]);
    expect(decision.studentId).toBe("stu_1");
    expect(decision.toGradeLevel).toBe("Grade 10");
    expect(decision.departsFromRecommendation).toBe(false);
  });

  it("refuses an empty batch", () => {
    expect(() => validateDecisions([])).toThrow(/nothing to roll over/);
    expect(() => validateDecisions(undefined)).toThrow(/nothing to roll over/);
  });

  it("refuses more than one page at a time", () => {
    const many = Array.from({length: MAX_DECISIONS_PER_CALL + 1}, (_, i) => ({
      ...promoted,
      studentId: `stu_${i}`,
    }));
    expect(() => validateDecisions(many)).toThrow(/Too many students/);
  });

  it("refuses the same student twice in one batch", () => {
    // A client bug, and applying both would move them twice.
    expect(() => validateDecisions([promoted, promoted])).toThrow(/appears twice/);
  });

  it("refuses a promotion with nowhere to go", () => {
    // The failure the whole feature exists to avoid: the student's year
    // is blanked and they are missing off every class list in September.
    expect(() =>
      validateDecisions([{...promoted, toGradeLevel: "", toSection: ""}])
    ).toThrow(/no \n?year and section to go to/s);

    expect(() =>
      validateDecisions([{...promoted, toSection: "   "}])
    ).toThrow(/year and section/);
  });

  it("lets a retention through with nowhere to go, because it goes nowhere", () => {
    const [decision] = validateDecisions([
      {...promoted, outcome: "retained", toGradeLevel: "", toSection: ""},
    ]);
    expect(decision.outcome).toBe("retained");
  });

  it("refuses an outcome that is not one", () => {
    expect(() => validateDecisions([{...promoted, outcome: "expelled"}]))
      .toThrow(/is not an outcome/);
  });

  it("insists every decision carries what was recommended", () => {
    // So a departure from the recommendation stays visible afterwards
    // rather than looking like what the marks said all along.
    expect(() => validateDecisions([{...promoted, recommended: ""}]))
      .toThrow(/carry the outcome that was recommended/);
  });

  it("marks a decision that departs from the recommendation", () => {
    const [decision] = validateDecisions([
      {...promoted, recommended: "retained", outcome: "promoted"},
    ]);
    expect(decision.departsFromRecommendation).toBe(true);
  });

  it("does not second-guess the registrar's departure", () => {
    // Promoting a student the marks say to retain is theirs to decide.
    // The record keeps both; the server does not refuse it.
    expect(() =>
      validateDecisions([{...promoted, recommended: "retained"}])
    ).not.toThrow();
  });

  it("refuses a decision with no student on it", () => {
    expect(() => validateDecisions([{...promoted, studentId: "  "}]))
      .toThrow(/no student on it/);
  });

  it("refuses a general average that is not a number", () => {
    expect(() =>
      validateDecisions([{...promoted, generalAverage: Number.NaN}])
    ).toThrow(/has to be a number/);
  });

  it("takes a missing general average as none", () => {
    const [decision] = validateDecisions([{...promoted, generalAverage: undefined}]);
    expect(decision.generalAverage).toBeNull();
  });

  it("keeps the failed subjects, dropping the blanks", () => {
    const [decision] = validateDecisions([
      {...promoted, failedSubjects: ["Mathematics", "  ", "Science"]},
    ]);
    expect(decision.failedSubjects).toEqual(["Mathematics", "Science"]);
  });

  it("falls back to the student id when no name came with it", () => {
    // So an error message never reads "Stopped at undefined".
    const [decision] = validateDecisions([{...promoted, studentName: ""}]);
    expect(decision.studentName).toBe("stu_1");
  });
});

describe("studentUpdateFor", () => {
  const base = {
    studentId: "stu_1",
    studentName: "Miguel Torres",
    recommended: "promoted",
    fromGradeLevel: "Grade 9",
    fromSection: "Grade 9 - Rizal",
    toGradeLevel: "Grade 10",
    toSection: "Grade 10 - Rizal",
    generalAverage: 88,
    failedSubjects: [],
    departsFromRecommendation: false,
  };

  it("moves a promoted student", () => {
    expect(studentUpdateFor({...base, outcome: "promoted"})).toEqual({
      gradeLevel: "Grade 10",
      section: "Grade 10 - Rizal",
    });
  });

  it("marks a graduate without deleting them", () => {
    // They come back for a transcript years later, and the Form 137 has
    // to still be there.
    expect(studentUpdateFor({...base, outcome: "graduated"})).toEqual({
      status: "graduated",
    });
  });

  it("changes nothing for the three that go nowhere", () => {
    for (const outcome of ["retained", "conditional", "held"]) {
      expect(studentUpdateFor({...base, outcome})).toBeNull();
    }
  });
});
