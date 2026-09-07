import {
  COMPONENT_LABELS,
  GradingError,
  classKey,
  isGradingComponent,
  round2,
  scoreDocId,
  validateAssessment,
  validateScore,
} from "../../../src/shared/grading/assessment";
import {
  balances,
  validateWeights,
  weightFor,
  weightTotal,
  weightsFromDoc,
} from "../../../src/shared/grading/weights";

/**
 * What a piece of work and a mark against it may be.
 *
 * The identity is the point. A mark used to be posted and never
 * replaced, and the quarterly arithmetic sums the scores and the
 * maximums inside a component -- so a teacher correcting 80-out-of-10 to
 * 8-out-of-10 left the child on 88 out of 20, with nothing on any screen
 * saying so.
 */

const ok = {
  subject: "Mathematics",
  section: "Grade 10 - Rizal",
  term: "2nd Quarter",
  title: "Quiz 1",
  component: "written_work",
  maxScore: 20,
};

describe("a piece of work", () => {
  it("needs a class, a quarter, a name and a total", () => {
    const assessment = validateAssessment(ok);
    expect(assessment.title).toBe("Quiz 1");
    expect(assessment.maxScore).toBe(20);

    for (const missing of ["subject", "section", "term", "title"]) {
      expect(() => validateAssessment({...ok, [missing]: "   "})).toThrow(GradingError);
      expect(() => validateAssessment({...ok, [missing]: null})).toThrow(GradingError);
    }
  });

  it("belongs to exactly one of the three components", () => {
    for (const component of ["written_work", "performance_task", "quarterly_assessment"]) {
      expect(isGradingComponent(component)).toBe(true);
      expect(validateAssessment({...ok, component}).component).toBe(component);
    }
    expect(isGradingComponent("homework")).toBe(false);
    expect(() => validateAssessment({...ok, component: "homework"})).toThrow(
      /which component/i
    );
    // A score filed under nothing cannot be weighted, and the whole
    // quarterly grade rests on this one choice being right.
    expect(() => validateAssessment({...ok, component: undefined})).toThrow();
  });

  it("refuses a total that is not a number", () => {
    // `NaN <= 0` is false, so a guard written as a comparison waves it
    // through -- and a NaN total makes every percentage in the component
    // NaN from then on.
    for (const bad of [NaN, Infinity, -Infinity, "twenty", null, undefined]) {
      expect(() => validateAssessment({...ok, maxScore: bad})).toThrow(
        /has to be a number/i
      );
    }
  });

  it("refuses a total of nothing", () => {
    // A piece of work worth zero cannot contribute to a percentage, and
    // counting it would make the denominator wrong.
    expect(() => validateAssessment({...ok, maxScore: 0})).toThrow(/more than zero/i);
    expect(() => validateAssessment({...ok, maxScore: -5})).toThrow(/more than zero/i);
  });

  it("trims what a school types", () => {
    const assessment = validateAssessment({...ok, title: "  Quiz 1  ", subject: " Mathematics "});
    expect(assessment.title).toBe("Quiz 1");
    expect(assessment.subject).toBe("Mathematics");
  });

  it("labels the three components the way a report card does", () => {
    expect(COMPONENT_LABELS.written_work).toBe("Written Work");
    expect(COMPONENT_LABELS.performance_task).toBe("Performance Tasks");
    expect(COMPONENT_LABELS.quarterly_assessment).toBe("Quarterly Assessment");
  });
});

describe("a mark against it", () => {
  it("is a number between nothing and the total", () => {
    expect(validateScore(18, 20)).toBe(18);
    expect(validateScore(0, 20)).toBe(0);
    expect(validateScore(20, 20)).toBe(20);
  });

  it("is blank when nothing was entered, and blank is not zero", () => {
    // A child who did not sit the quiz has the work left out of both
    // their score and the total it is over. A zero counts the total
    // against them. Collapsing the two marks an absent child as having
    // failed.
    expect(validateScore(null, 20)).toBeNull();
    expect(validateScore(undefined, 20)).toBeNull();
    expect(validateScore("", 20)).toBeNull();
    expect(validateScore(0, 20)).toBe(0);
  });

  it("refuses a score that is not a number", () => {
    for (const bad of [NaN, Infinity, "eighteen"]) {
      expect(() => validateScore(bad, 20)).toThrow(/has to be a number/i);
    }
  });

  it("refuses a negative one", () => {
    expect(() => validateScore(-1, 20)).toThrow(/cannot be negative/i);
  });

  it("refuses one higher than the work is out of, and says both numbers", () => {
    // Almost always the two columns filled in the wrong order. A school
    // that genuinely gives bonus marks raises the total the work is out
    // of, which is the same arithmetic said honestly.
    expect(() => validateScore(25, 20)).toThrow(/25 is higher than the 20/);
  });

  it("reads a number written as text, because a spreadsheet writes them that way", () => {
    expect(validateScore("18", 20)).toBe(18);
    expect(validateScore(" 18.5 ", 20)).toBe(18.5);
  });
});

describe("where a mark lives", () => {
  it("is one document per student per piece of work", () => {
    // The fix, in one line. Entering a corrected score writes to the
    // same id and replaces it, instead of adding a second row the
    // arithmetic sums.
    expect(scoreDocId("as_1", "stu_1")).toBe("as_1_stu_1");
    expect(scoreDocId("as_1", "stu_1")).toBe(scoreDocId("as_1", "stu_1"));
    expect(scoreDocId("as_1", "stu_2")).not.toBe(scoreDocId("as_1", "stu_1"));
  });
});

describe("the key one class is filed under", () => {
  it("is the same however the school typed the name", () => {
    // "Mathematics" and "mathematics " are one class, not two sets of
    // weights nobody can tell apart.
    expect(classKey("Mathematics", "Grade 10 - Rizal")).toBe(
      classKey(" mathematics ", "GRADE 10 - RIZAL")
    );
  });

  it("survives the punctuation a section name actually has", () => {
    expect(classKey("Mathematics", "Grade 10 - Rizal")).toBe(
      "mathematics__grade-10-rizal"
    );
    // Nothing that could be read as a path.
    expect(classKey("A/B", "C/D")).not.toContain("/");
  });

  it("keeps two different classes apart", () => {
    expect(classKey("Mathematics", "Grade 10 - Rizal")).not.toBe(
      classKey("Mathematics", "Grade 10 - Mabini")
    );
    expect(classKey("Mathematics", "Rizal", "Q1")).not.toBe(
      classKey("Mathematics", "Rizal", "Q2")
    );
  });

  it("does not collapse a name that is only punctuation", () => {
    expect(classKey("---", "Rizal")).toBe("none__rizal");
  });
});

describe("what each component counts for", () => {
  const depEdScienceMaths = {
    writtenWork: 40,
    performanceTask: 40,
    quarterlyAssessment: 20,
  };

  it("adds up to a hundred, or it is refused", () => {
    // The one misconfiguration that does not announce itself: 30/50/30
    // produces grades that look entirely plausible and are wrong for
    // every child in the class, all quarter.
    expect(balances(depEdScienceMaths)).toBe(true);
    expect(validateWeights(depEdScienceMaths)).toEqual(depEdScienceMaths);

    expect(() =>
      validateWeights({writtenWork: 30, performanceTask: 50, quarterlyAssessment: 30})
    ).toThrow(/add up to 100/i);
    expect(() =>
      validateWeights({writtenWork: 30, performanceTask: 50, quarterlyAssessment: 30})
    ).toThrow(/110/);
  });

  it("names the component that is wrong rather than the set", () => {
    expect(() =>
      validateWeights({...depEdScienceMaths, writtenWork: -1})
    ).toThrow(/Written work cannot be negative/);
    expect(() =>
      validateWeights({...depEdScienceMaths, performanceTask: 101})
    ).toThrow(/Performance tasks cannot be more than 100/);
    expect(() =>
      validateWeights({...depEdScienceMaths, quarterlyAssessment: NaN})
    ).toThrow(/Quarterly assessment has to be a number/);
  });

  it("reads the weight for one component", () => {
    expect(weightFor(depEdScienceMaths, "written_work")).toBe(40);
    expect(weightFor(depEdScienceMaths, "performance_task")).toBe(40);
    expect(weightFor(depEdScienceMaths, "quarterly_assessment")).toBe(20);
    expect(weightTotal(depEdScienceMaths)).toBe(100);
  });

  it("ignores a stored set that does not balance", () => {
    // It should be impossible -- the callable refuses to write one --
    // and grading a class on a scheme known to be broken would be worse
    // than ignoring it, because the grades would look ordinary.
    expect(weightsFromDoc({writtenWork: 40, performanceTask: 40, quarterlyAssessment: 20}))
      .toEqual(depEdScienceMaths);
    expect(weightsFromDoc({writtenWork: 30, performanceTask: 50, quarterlyAssessment: 30}))
      .toBeNull();
    expect(weightsFromDoc({writtenWork: 40})).toBeNull();
    expect(weightsFromDoc(undefined)).toBeNull();
  });
});

describe("rounding", () => {
  it("goes to two places, a half away from zero", () => {
    expect(round2(0.125)).toBe(0.13);
    expect(round2(-0.125)).toBe(-0.13);
    expect(round2(18)).toBe(18);
  });
});
