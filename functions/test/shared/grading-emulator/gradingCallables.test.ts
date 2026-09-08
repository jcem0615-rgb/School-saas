/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/grading-emulator"
 *
 * The four callables that write a grade, against a real Firestore.
 *
 * The arithmetic is covered pure in test/shared/grading/ and, for the
 * quarterly grade itself, in the Dart suite. What is tested here is the
 * thing that only a real database shows: that a mark entered twice is
 * one mark.
 *
 * That was the module's worst defect and it was silent. `submitGrade`
 * wrote a new document every time, and `computeQuarterlyGrade` sums the
 * scores *and the maximums* inside a component -- so a teacher who typed
 * 80 out of 10, noticed, and re-entered 8 out of 10 ended the quarter
 * with 88 out of 20. Nothing errored and no screen said anything.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_grading";
const OTHER_SCHOOL = "school_grading_other";
const SUBJECT = "Mathematics";
const SECTION = "Grade 10 - Rizal";
const TERM = "2nd Quarter";

/* eslint-disable @typescript-eslint/no-explicit-any */
let callSaveAssessment: any;
let callSaveScores: any;
let callSetWeights: any;
let callPostMark: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

function caller(role: string, uid = `${role}_1`, schoolId: string | undefined = SCHOOL) {
  return {
    uid,
    token: {role, schoolId, status: "active", mustChangePassword: false, name: `${role} one`},
  };
}

const assessment = (over: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  subject: SUBJECT,
  section: SECTION,
  term: TERM,
  title: "Quiz 1",
  component: "written_work",
  maxScore: 20,
  ...over,
});

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.grades(schoolId),
    FirestorePaths.classAssessments(schoolId),
    FirestorePaths.classWeights(schoolId),
    FirestorePaths.auditLog(schoolId),
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function marksFor(assessmentId: string, schoolId = SCHOOL) {
  const snap = await db()
    .collection(FirestorePaths.grades(schoolId))
    .where("assessmentId", "==", assessmentId)
    .get();
  return snap.docs
    .map((d) => ({id: d.id, ...d.data()} as Record<string, unknown>))
    .filter((row) => row.isDeleted !== true);
}

describe("keeping a class record", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const [a, s, w, p] = await Promise.all([
      import("../../../src/callable/grading/saveClassAssessment"),
      import("../../../src/callable/grading/saveAssessmentScores"),
      import("../../../src/callable/grading/setClassWeights"),
      import("../../../src/callable/grading/postGradeMark"),
    ]);
    callSaveAssessment = fft.wrap(a.saveClassAssessment);
    callSaveScores = fft.wrap(s.saveAssessmentScores);
    callSetWeights = fft.wrap(w.setClassWeights);
    callPostMark = fft.wrap(p.postGradeMark);
  });

  afterAll(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    fft.cleanup();
  });

  beforeEach(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
  });

  describe("who may mark", () => {
    it("is the teaching side of the school", async () => {
      for (const role of ["faculty", "admin"]) {
        const result = await callSaveAssessment({
          data: assessment({title: `Quiz ${role}`}),
          auth: caller(role),
        } as never);
        expect(result.assessmentId).toBeTruthy();
      }
    });

    it("is not the registrar, not a supervisor, and not a student", async () => {
      // Director and Principal supervise; marking is the teaching side's.
      for (const role of ["registrar", "director", "principal", "student", "parent", "staff"]) {
        await expect(
          callSaveAssessment({data: assessment(), auth: caller(role)} as never)
        ).rejects.toThrow(/role/i);
      }
    });

    it("is nobody at all when signed out", async () => {
      await expect(callSaveAssessment({data: assessment()} as never)).rejects.toThrow(
        /signed in/i
      );
    });

    it("is not a teacher at another school", async () => {
      await expect(
        callSaveAssessment({
          data: assessment(),
          auth: caller("faculty", "faculty_b", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow(/access/i);
    });
  });

  describe("a mark entered twice", () => {
    it("is one mark, not two", async () => {
      // The defect this whole change exists for.
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [{studentId: "stu_1", studentName: "Miguel Torres", score: 8}],
        },
        auth: caller("faculty"),
      } as never);
      // The teacher notices and re-enters.
      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [{studentId: "stu_1", studentName: "Miguel Torres", score: 18}],
        },
        auth: caller("faculty"),
      } as never);

      const marks = await marksFor(assessmentId);
      expect(marks).toHaveLength(1);
      expect(marks[0].score).toBe(18);
      // And the total behind it did not double either, which is the
      // half that made the old bug invisible: 8/20 then 18/20 became
      // 26 out of 40.
      expect(marks[0].maxScore).toBe(20);
    });

    it("is one mark through the single-mark path too", async () => {
      // The import and the per-student dialog use this one. Running an
      // import twice used to double a child's written work.
      const post = () =>
        callPostMark({
          data: {
            schoolId: SCHOOL,
            studentId: "stu_1",
            studentName: "Miguel Torres",
            subject: SUBJECT,
            section: SECTION,
            term: TERM,
            component: "written_work",
            score: 18,
            maxScore: 20,
            remarks: "Quiz 1",
          },
          auth: caller("faculty"),
        } as never);

      const first = await post();
      await post();

      const marks = await marksFor(first.assessmentId);
      expect(marks).toHaveLength(1);
      expect(marks[0].score).toBe(18);

      // And one column, not two.
      const columns = await db().collection(FirestorePaths.classAssessments(SCHOOL)).get();
      expect(columns.docs).toHaveLength(1);
    });
  });

  describe("a whole column at once", () => {
    it("marks the class and says how many", async () => {
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      const result = await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [
            {studentId: "stu_1", studentName: "Miguel", score: 18},
            {studentId: "stu_2", studentName: "Bea", score: 16},
            {studentId: "stu_3", studentName: "Andrea", score: 19},
          ],
        },
        auth: caller("faculty"),
      } as never);

      expect(result.saved).toBe(3);
      expect(await marksFor(assessmentId)).toHaveLength(3);
    });

    it("takes the total from the piece of work, not from the caller", async () => {
      // A client that could name the denominator could hand a class any
      // percentage it liked.
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          maxScore: 1,
          scores: [{studentId: "stu_1", studentName: "Miguel", score: 18, maxScore: 1}],
        },
        auth: caller("faculty"),
      } as never);

      const marks = await marksFor(assessmentId);
      expect(marks[0].maxScore).toBe(20);
    });

    it("stamps who marked it from the token, never from the payload", async () => {
      // A grade is a record of what a named teacher marked. The old
      // update rule pinned only studentId, so this was writable.
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          submittedByName: "Somebody Else",
          scores: [
            {
              studentId: "stu_1",
              studentName: "Miguel",
              score: 18,
              submittedByName: "Somebody Else",
            },
          ],
        },
        auth: caller("faculty"),
      } as never);

      const marks = await marksFor(assessmentId);
      expect(marks[0].submittedByName).toBe("faculty one");
    });

    it("leaves a blank blank, and does not call it a zero", async () => {
      // A child who did not sit the quiz has the work left out of both
      // their score and the total it is over. Calling it zero marks
      // them as having failed something they were absent from.
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [
            {studentId: "stu_1", studentName: "Miguel", score: 18},
            {studentId: "stu_2", studentName: "Trisha", score: null},
          ],
        },
        auth: caller("faculty"),
      } as never);

      const marks = await marksFor(assessmentId);
      expect(marks).toHaveLength(1);
      expect(marks[0].studentId).toBe("stu_1");
    });

    it("clears a mark entered by mistake", async () => {
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);
      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [{studentId: "stu_1", studentName: "Miguel", score: 18}],
        },
        auth: caller("faculty"),
      } as never);
      expect(await marksFor(assessmentId)).toHaveLength(1);

      const result = await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [{studentId: "stu_1", studentName: "Miguel", score: null}],
        },
        auth: caller("faculty"),
      } as never);
      expect(result.cleared).toBe(1);
      expect(await marksFor(assessmentId)).toHaveLength(0);
    });

    it("refuses a score above what the work is out of, naming the child", async () => {
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);

      await expect(
        callSaveScores({
          data: {
            schoolId: SCHOOL,
            assessmentId,
            scores: [{studentId: "stu_1", studentName: "Miguel Torres", score: 200}],
          },
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/Miguel Torres.*higher than the 20/);
      expect(await marksFor(assessmentId)).toHaveLength(0);
    });

    it("refuses the same child twice in one save", async () => {
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);
      await expect(
        callSaveScores({
          data: {
            schoolId: SCHOOL,
            assessmentId,
            scores: [
              {studentId: "stu_1", studentName: "Miguel", score: 18},
              {studentId: "stu_1", studentName: "Miguel", score: 12},
            ],
          },
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/twice/i);
    });

    it("refuses to mark against a piece of work that is gone", async () => {
      await expect(
        callSaveScores({
          data: {
            schoolId: SCHOOL,
            assessmentId: "as_nothing",
            scores: [{studentId: "stu_1", score: 1}],
          },
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/no longer on file/i);
    });
  });

  describe("changing what a piece of work is out of", () => {
    it("keeps the marks and names the ones that no longer fit", async () => {
      // Either number could be the right one, and only the teacher
      // knows which. Clamping would change a mark without saying so.
      const {assessmentId} = await callSaveAssessment({
        data: assessment({maxScore: 40}),
        auth: caller("faculty"),
      } as never);
      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [
            {studentId: "stu_1", studentName: "Miguel Torres", score: 34},
            {studentId: "stu_2", studentName: "Bea Torres", score: 18},
          ],
        },
        auth: caller("faculty"),
      } as never);

      const result = await callSaveAssessment({
        data: assessment({assessmentId, maxScore: 20}),
        auth: caller("faculty"),
      } as never);

      expect(result.marksOverMax).toEqual(["Miguel Torres"]);
      const marks = await marksFor(assessmentId);
      expect(marks).toHaveLength(2);
      expect(marks.find((m) => m.studentId === "stu_1")!.score).toBe(34);
    });
  });

  describe("what each component counts for", () => {
    const weights = {
      schoolId: SCHOOL,
      subject: SUBJECT,
      section: SECTION,
      writtenWork: 40,
      performanceTask: 40,
      quarterlyAssessment: 20,
    };

    it("is stored for the class, with the name of whoever set it", async () => {
      await callSetWeights({data: weights, auth: caller("faculty")} as never);
      const snap = await db()
        .doc(FirestorePaths.classWeightsDoc(SCHOOL, "mathematics__grade-10-rizal"))
        .get();
      expect(snap.exists).toBe(true);
      expect(snap.data()!.writtenWork).toBe(40);
      // A split nobody agreed to should be visible, not silently in
      // effect.
      expect(snap.data()!.setByName).toBe("faculty one");
    });

    it("is refused unless the three add up to a hundred", async () => {
      await expect(
        callSetWeights({
          data: {...weights, quarterlyAssessment: 30},
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/add up to 100/i);

      const snap = await db()
        .doc(FirestorePaths.classWeightsDoc(SCHOOL, "mathematics__grade-10-rizal"))
        .get();
      expect(snap.exists).toBe(false);
    });

    it("can be cleared, so the class goes back to the school's scheme", async () => {
      await callSetWeights({data: weights, auth: caller("faculty")} as never);
      const result = await callSetWeights({
        data: {schoolId: SCHOOL, subject: SUBJECT, section: SECTION, clear: true},
        auth: caller("faculty"),
      } as never);
      expect(result.cleared).toBe(true);

      const snap = await db()
        .doc(FirestorePaths.classWeightsDoc(SCHOOL, "mathematics__grade-10-rizal"))
        .get();
      expect(snap.exists).toBe(false);
    });

    it("is one record however the class name was typed", async () => {
      await callSetWeights({data: weights, auth: caller("faculty")} as never);
      await callSetWeights({
        data: {...weights, subject: " mathematics ", section: "GRADE 10 - RIZAL"},
        auth: caller("faculty"),
      } as never);

      const snap = await db().collection(FirestorePaths.classWeights(SCHOOL)).get();
      expect(snap.docs).toHaveLength(1);
    });
  });

  describe("the audit trail", () => {
    it("records the marking, with the teacher's name against it", async () => {
      const {assessmentId} = await callSaveAssessment({
        data: assessment(),
        auth: caller("faculty"),
      } as never);
      await callSaveScores({
        data: {
          schoolId: SCHOOL,
          assessmentId,
          scores: [{studentId: "stu_1", studentName: "Miguel", score: 18}],
        },
        auth: caller("faculty"),
      } as never);

      const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
      const entry = snap.docs.map((d) => d.data()).find((d) => d.action === "scores_saved");
      expect(entry).toBeDefined();
      expect(entry!.userName).toBe("faculty one");
      expect((entry!.newValue as {marked: number}).marked).toBe(1);
    });
  });
});
