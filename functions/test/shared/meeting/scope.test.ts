import {
  LearnerScope,
  scopeFrom,
  scopeOfRoll,
  scopeRefusal,
} from "../../../src/shared/meeting/scope";

/**
 * The fourth lock on a video lesson, after the school, the register and
 * the passcode.
 *
 * It exists because all three of those can be true of somebody who has
 * since moved: promoted a grade, transferred between sections,
 * withdrawn. The register is a photograph of the roll when the lesson
 * opened; this compares the person at the door against the lesson's
 * scope as they are now.
 */
describe("who belongs in a lesson", () => {
  const SCHOOL = "school-1";

  const pupil: LearnerScope = {
    schoolId: SCHOOL,
    status: "enrolled",
    section: "Grade 10 - Rizal",
    gradeLevel: "10",
    educationLevel: "junior_high",
    department: "Junior High School",
    programId: "jhs-core",
  };

  const lesson = scopeOfRoll([pupil]);

  describe("the scope of a roll", () => {
    it("is read off the records the roll was built from", () => {
      expect(lesson).toEqual({
        section: ["Grade 10 - Rizal"],
        gradeLevel: ["10"],
        educationLevel: ["junior_high"],
        department: ["Junior High School"],
        programId: ["jhs-core"],
      });
    });

    it("holds every value when a lesson draws from several sections", () => {
      // An elective, a college course, a remedial group pulled from
      // three sections. One lesson, several sections in it.
      const mixed = scopeOfRoll([
        pupil,
        {...pupil, section: "Grade 10 - Bonifacio"},
        {...pupil, section: "Grade 10 - Rizal"},
      ]);

      expect(mixed.section).toEqual(["Grade 10 - Bonifacio", "Grade 10 - Rizal"]);
      expect(mixed.gradeLevel).toEqual(["10"]);
    });

    it("leaves out a dimension no record carries", () => {
      const sparse = scopeOfRoll([
        {schoolId: SCHOOL, section: "Grade 7 - Mabini"},
      ]);

      expect(sparse.section).toEqual(["Grade 7 - Mabini"]);
      expect(sparse.gradeLevel).toBeUndefined();
      expect(sparse.department).toBeUndefined();
    });

    it("is empty for an empty roll rather than a scope of nothing", () => {
      expect(scopeOfRoll([])).toEqual({});
    });
  });

  describe("reading a stored scope", () => {
    it("survives the trip to Firestore and back", () => {
      expect(scopeFrom(lesson)).toEqual(lesson);
    });

    it("ignores a session that has no scope on it", () => {
      // Sessions opened before this existed. Their lessons still have
      // to be joinable.
      for (const stored of [undefined, null, "", 42, [], {}]) {
        expect(scopeFrom(stored)).toEqual({});
      }
    });

    it("ignores rubbish inside a scope rather than trusting it", () => {
      expect(
        scopeFrom({section: ["Grade 10 - Rizal", "", 7, null], gradeLevel: "10"})
      ).toEqual({section: ["Grade 10 - Rizal"]});
    });
  });

  describe("at the door", () => {
    const refuse = (learner: LearnerScope) =>
      scopeRefusal(lesson, learner, {schoolId: SCHOOL});

    it("lets in the child the lesson was opened for", () => {
      expect(refuse(pupil)).toBeNull();
    });

    it("refuses a child of another school", () => {
      expect(refuse({...pupil, schoolId: "school-2"})).toContain("another school");
    });

    it("refuses a child who has been moved to another section", () => {
      // The mark from this morning still points at the lesson. The
      // child does not belong in it any more.
      expect(refuse({...pupil, section: "Grade 10 - Bonifacio"}))
        .toContain("another section");
    });

    it("refuses a child who has been promoted out of the grade", () => {
      expect(refuse({...pupil, gradeLevel: "11"})).toContain("another grade level");
    });

    it("refuses a child moved to another department or programme", () => {
      expect(refuse({...pupil, department: "Senior High School"}))
        .toContain("another department");
      expect(refuse({...pupil, programId: "shs-stem"}))
        .toContain("another programme");
      expect(refuse({...pupil, educationLevel: "senior_high"}))
        .toContain("another education level");
    });

    it("refuses a child who is no longer enrolled", () => {
      for (const status of ["transferred", "withdrawn", "graduated"]) {
        expect(refuse({...pupil, status})).toContain("no longer enrolled");
      }
    });

    it("says which lock shut, because a teacher has to act on it", () => {
      // "You are not in that class" told a teacher nothing when a child
      // had been moved to another section that morning.
      expect(refuse({...pupil, section: "Grade 10 - Bonifacio"}))
        .not.toBe(refuse({...pupil, gradeLevel: "11"}));
    });
  });

  describe("records that predate a field", () => {
    it("does not lock a school out over a dimension it never filled in", () => {
      // A student enrolled before `department` existed has no value for
      // it. Refusing them would enforce a rule about records that have
      // not moved, by keeping a child out of their own lesson.
      const older: LearnerScope = {
        schoolId: SCHOOL,
        status: "enrolled",
        section: "Grade 10 - Rizal",
      };

      expect(scopeRefusal(lesson, older, {schoolId: SCHOOL})).toBeNull();
    });

    it("but never waives the section", () => {
      // Every lesson and every student record has always had one, so a
      // missing section is a record that is wrong rather than old.
      const sectionless: LearnerScope = {
        schoolId: SCHOOL,
        status: "enrolled",
      };

      expect(scopeRefusal(lesson, sectionless, {schoolId: SCHOOL}))
        .toContain("another section");
    });

    it("lets an unscoped lesson be joined by the register alone", () => {
      // Sessions opened before this existed. The register and the
      // passcode still decide; this simply has nothing to add.
      expect(scopeRefusal({}, pupil, {schoolId: SCHOOL})).toBeNull();
      expect(
        scopeRefusal({}, {...pupil, gradeLevel: "11"}, {schoolId: SCHOOL})
      ).toBeNull();
    });
  });
});
