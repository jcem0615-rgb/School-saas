import * as admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});
const SCHOOL = "school_a";
const OTHER_SCHOOL = "school_b";

let callNormalise: any;

function db() {
  return admin.firestore();
}

function caller(role: string, uid = `${role}_1`, schoolId: string | undefined = SCHOOL) {
  return {
    uid,
    token: {role, schoolId, status: "active", mustChangePassword: false, name: `${role} one`},
  };
}

/** A mark as the old free-text path wrote one: no assessment id. */
async function mark(
  id: string,
  over: Record<string, unknown> = {},
  schoolId = SCHOOL
) {
  await db()
    .doc(`${FirestorePaths.grades(schoolId)}/${id}`)
    .set({
      studentId: "stu_1",
      studentName: "Bea Torres",
      subject: "Mathematics",
      section: "Grade 10 - Rizal",
      term: "Q1",
      component: "written_work",
      score: 18,
      maxScore: 20,
      isDeleted: false,
      ...over,
    });
}

async function termOf(id: string, schoolId = SCHOOL) {
  const doc = await db().doc(`${FirestorePaths.grades(schoolId)}/${id}`).get();
  return doc.data()?.term;
}

async function wipe(schoolId: string) {
  for (const path of [FirestorePaths.grades(schoolId), FirestorePaths.auditLog(schoolId)]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

/// Repairing marks filed under a term no screen queries.
///
/// The defect: Grade Submission shipped a free-text term box defaulting
/// to "Q1" while the class record's dropdown offered "1st Quarter". Every
/// query on `term` is an equality match, so those marks were saved,
/// confirmed, and invisible.
describe("normalising the terms marks were filed under", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const module = await import("../../../src/callable/grading/normaliseGradeTerms");
    callNormalise = fft.wrap(module.normaliseGradeTerms);
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

  describe("reporting before writing", () => {
    it("says what it would do and changes nothing", async () => {
      await mark("g1");
      await mark("g2", {studentId: "stu_2", term: "q2"});

      const report = await callNormalise({
        data: {schoolId: SCHOOL},
        auth: caller("admin"),
      } as never);

      expect(report.applied).toBe(false);
      expect(report.scanned).toBe(2);
      expect(report.moved).toBe(2);
      expect(report.moves).toEqual(
        expect.arrayContaining([
          {from: "Q1", to: "1st Quarter", count: 1},
          {from: "q2", to: "2nd Quarter", count: 1},
        ])
      );
      // The whole point of a dry run.
      expect(await termOf("g1")).toBe("Q1");
      expect(await termOf("g2")).toBe("q2");
    });

    it("reports nothing to do when every mark is already canonical", async () => {
      await mark("g1", {term: "1st Quarter"});
      const report = await callNormalise({
        data: {schoolId: SCHOOL},
        auth: caller("admin"),
      } as never);
      expect(report.moved).toBe(0);
      expect(report.moves).toEqual([]);
    });
  });

  describe("applying", () => {
    it("moves the marks and leaves the canonical ones alone", async () => {
      await mark("g1");
      await mark("g2", {term: "2nd Quarter", studentId: "stu_2"});

      const report = await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      expect(report.applied).toBe(true);
      expect(report.moved).toBe(1);
      expect(await termOf("g1")).toBe("1st Quarter");
      expect(await termOf("g2")).toBe("2nd Quarter");
    });

    it("keeps a term it does not recognise", async () => {
      // A school running its own names keeps them. Rewriting "Prelim" to
      // a quarter would be this software deciding how a school divides
      // its year.
      await mark("g1", {term: "Prelim"});
      await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);
      expect(await termOf("g1")).toBe("Prelim");
    });

    it("writes an audit entry naming what moved", async () => {
      await mark("g1");
      await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      const log = await db()
        .collection(FirestorePaths.auditLog(SCHOOL))
        .where("action", "==", "grade_terms_normalised")
        .get();
      expect(log.size).toBe(1);
      expect(log.docs[0].data().remarks).toMatch(/1 mark moved/);
    });

    it("does not touch another school's marks", async () => {
      await mark("g1");
      await mark("other", {}, OTHER_SCHOOL);
      await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);
      expect(await termOf("other", OTHER_SCHOOL)).toBe("Q1");
    });
  });

  describe("the double-count it refuses to create", () => {
    it("skips a mark whose twin already sits in the destination", async () => {
      // The same quiz entered through both screens. Moving the first
      // turns 18/20 into 36/40 -- a wrong grade produced by the repair.
      await mark("loose_q1", {term: "Q1"});
      await mark("loose_canonical", {term: "1st Quarter"});

      const report = await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      expect(report.moved).toBe(0);
      expect(report.skipped).toHaveLength(1);
      expect(report.skipped[0]).toMatchObject({from: "Q1", to: "1st Quarter", count: 1});
      expect(report.skipped[0].reason).toMatch(/twice/);
      expect(await termOf("loose_q1")).toBe("Q1");
    });

    it("moves a mark that only looks similar", async () => {
      // Same student and component, different score: two real pieces of
      // work, and the second belongs in the quarter with the first.
      await mark("g1", {term: "Q1", score: 15});
      await mark("g2", {term: "1st Quarter", score: 18});

      const report = await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      expect(report.moved).toBe(1);
      expect(report.skipped).toEqual([]);
      expect(await termOf("g1")).toBe("1st Quarter");
    });

    it("does not let two wrong marks collide onto each other", async () => {
      // Both under "Q1", identical. Moving both would put two copies in
      // the first quarter -- the collision created by the repair itself
      // rather than found there.
      await mark("dup_a", {term: "Q1"});
      await mark("dup_b", {term: "q1"});

      const report = await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      expect(report.moved).toBe(1);
      expect(report.skipped).toHaveLength(1);
    });

    it("moves marks tied to a piece of work without checking for twins", async () => {
      // They cannot collide: a mark lives at {assessment}_{student}, so
      // one assessment and one student is one document.
      await mark("as_1_stu_1", {term: "Q1", assessmentId: "as_1"});
      await mark("as_2_stu_1", {term: "Q1", assessmentId: "as_2"});

      const report = await callNormalise({
        data: {schoolId: SCHOOL, apply: true},
        auth: caller("admin"),
      } as never);

      expect(report.moved).toBe(2);
      expect(report.skipped).toEqual([]);
    });
  });

  describe("who may run it", () => {
    it("is the Admin, and nobody else", async () => {
      await mark("g1");
      for (const role of ["faculty", "registrar", "director", "principal", "student", "parent"]) {
        await expect(
          callNormalise({
            data: {schoolId: SCHOOL, apply: true},
            auth: caller(role),
          } as never)
        ).rejects.toThrow(/role/i);
      }
      expect(await termOf("g1")).toBe("Q1");
    });

    it("is not an admin at another school", async () => {
      await expect(
        callNormalise({
          data: {schoolId: SCHOOL},
          auth: caller("admin", "admin_b", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow(/access/i);
    });

    it("is nobody at all when signed out", async () => {
      await expect(
        callNormalise({data: {schoolId: SCHOOL}} as never)
      ).rejects.toThrow(/signed in/i);
    });
  });
});
