import {
  nextStagesFrom,
  requireLegalTransition,
  validateApplicant,
  validateExamResult,
  validateReservationFee,
} from "../../../src/shared/admissions/applicant";

/**
 * The server's half of the admissions pipeline.
 *
 * The client offers the right buttons; this is what holds when something
 * else calls the callable. The rule worth defending is that stages
 * cannot be set to whatever somebody expects -- a pipeline whose stages
 * are free-for-all stops meaning anything within a term, and the funnel
 * starts reporting offers the school never made.
 */
describe("nextStagesFrom", () => {
  it("offers one step forward, one back, and both endings", () => {
    expect(nextStagesFrom("exam_scheduled")).toEqual([
      "exam_taken",
      "applied",
      "declined",
      "withdrawn",
    ]);
  });

  it("has nowhere to go back to from the first stage", () => {
    expect(nextStagesFrom("inquiry")).toEqual(["applied", "declined", "withdrawn"]);
  });

  it("sends a family who came back to the beginning", () => {
    expect(nextStagesFrom("withdrawn")).toEqual(["inquiry"]);
    expect(nextStagesFrom("declined")).toEqual(["inquiry"]);
  });

  it("lets nothing out of enrolled", () => {
    // There is a student record behind it. Moving out would leave a
    // child enrolled and an applicant record saying they withdrew.
    expect(nextStagesFrom("enrolled")).toEqual([]);
  });
});

describe("requireLegalTransition", () => {
  it("allows the next step", () => {
    expect(() => requireLegalTransition("applied", "exam_scheduled")).not.toThrow();
  });

  it("allows a step back, so a mis-marked family can be corrected", () => {
    // Without this, people fix a wrong stage by making a second record
    // for the same child.
    expect(() => requireLegalTransition("offered", "exam_taken")).not.toThrow();
  });

  it("refuses a jump, and names what is allowed instead", () => {
    expect(() => requireLegalTransition("inquiry", "offered"))
      .toThrow(/can only move to: applied, declined, withdrawn/);
  });

  it("refuses moving somewhere they already are", () => {
    expect(() => requireLegalTransition("applied", "applied"))
      .toThrow(/already where they are/);
  });

  it("refuses setting enrolled at all", () => {
    // Enrolment creates the student record, so it is reached by
    // enrolling and not by setting a stage. An applicant marked enrolled
    // with no record is a child the school believes is enrolled and the
    // registrar cannot find.
    expect(() => requireLegalTransition("reserved", "enrolled"))
      .toThrow(/done by enrolling them rather than by setting the stage/);
  });

  it("refuses moving an enrolled applicant anywhere", () => {
    expect(() => requireLegalTransition("enrolled", "withdrawn"))
      .toThrow(/cannot be moved back out of it/);
  });
});

describe("validateApplicant", () => {
  const enquiry = {
    firstName: "Bea",
    lastName: "Marquez",
    educationLevel: "high_school",
    gradeLevel: "Grade 7",
    guardianName: "Alma Marquez",
    guardianPhone: "09171234567",
  };

  it("takes down an enquiry with the little it insists on", () => {
    const saved = validateApplicant(enquiry);
    expect(saved.firstName).toBe("Bea");
    expect(saved.gradeLevel).toBe("Grade 7");
    // Absent optional fields are stored as null, not "", so a later read
    // can tell "not asked" from "asked and blank".
    expect(saved.middleName).toBeNull();
    expect(saved.source).toBeNull();
  });

  it("insists on a name", () => {
    expect(() => validateApplicant({...enquiry, lastName: " "}))
      .toThrow(/name is required/);
  });

  it("insists on somebody to ring", () => {
    // An applicant nobody can contact is not a lead, it is a row.
    expect(() => validateApplicant({...enquiry, guardianPhone: ""}))
      .toThrow(/not a lead/);
    expect(() => validateApplicant({...enquiry, guardianName: ""}))
      .toThrow(/not a lead/);
  });

  it("insists on which year they are applying into", () => {
    expect(() => validateApplicant({...enquiry, gradeLevel: ""}))
      .toThrow(/year they are applying into/);
  });

  it("asks for nothing else, because the caller is still on the line", () => {
    // A form that refuses to save without a middle name is a form that
    // gets abandoned -- and then the enquiry is a note on paper again.
    expect(() => validateApplicant(enquiry)).not.toThrow();
  });
});

describe("validateExamResult", () => {
  it("takes a score and what it was out of", () => {
    expect(validateExamResult(68, 80)).toEqual({score: 68, maxScore: 80});
  });

  it("refuses a score above the paper", () => {
    // Almost always the two fields the wrong way round, and it would
    // rank a child above everybody who sat the same paper.
    expect(() => validateExamResult(80, 68)).toThrow(/right way round/);
  });

  it("refuses a paper out of nothing", () => {
    expect(() => validateExamResult(40, 0)).toThrow(/more than zero/);
  });

  it("refuses a negative or unreadable score", () => {
    expect(() => validateExamResult(-1, 80)).toThrow(/not a number/);
    expect(() => validateExamResult("absent", 80)).toThrow(/not a number/);
  });

  it("allows a zero, which is a real mark", () => {
    expect(validateExamResult(0, 80).score).toBe(0);
  });
});

describe("validateReservationFee", () => {
  it("rounds to centavos", () => {
    expect(validateReservationFee(2000.005)).toBe(2000.01);
  });

  it("refuses nothing, or less than nothing", () => {
    expect(() => validateReservationFee(0)).toThrow(/above zero/);
    expect(() => validateReservationFee(-500)).toThrow(/above zero/);
    expect(() => validateReservationFee("free")).toThrow(/above zero/);
  });
});
