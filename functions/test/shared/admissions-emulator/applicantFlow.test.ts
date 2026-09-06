/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/admissions-emulator"
 *
 * The three admissions callables against a real Firestore. The stage
 * arithmetic and the field validation are covered pure in
 * test/shared/admissions/applicant.test.ts; what is tested here is what
 * the pure functions cannot see -- who may call, what the records have to
 * look like first, what actually lands in Firestore, and the one case the
 * whole module is shaped around: two clicks arriving at once on Enrol.
 *
 * That last one is why this file exists rather than more unit tests.
 * `enrolApplicant` draws a student number outside a transaction and then
 * creates the student inside one, and a stubbed transaction cannot fail
 * the way a real one does. If the guard were wrong, one family would get
 * two student records -- two ledgers, two report cards, and a registrar
 * who finds out in March.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_admissions";
const OTHER_SCHOOL = "school_admissions_other";
const APPLICANT = "app_bea";

/* eslint-disable @typescript-eslint/no-explicit-any */
let callSave: any;
let callAdvance: any;
let callEnrol: any;
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

const enquiry = {
  firstName: "Bea",
  lastName: "Marquez",
  educationLevel: "high_school",
  gradeLevel: "Grade 7",
  guardianName: "Alma Marquez",
  guardianPhone: "09171234567",
};

async function applicantDoc(id = APPLICANT, schoolId = SCHOOL) {
  const snap = await db().doc(FirestorePaths.applicantDoc(schoolId, id)).get();
  return snap.data();
}

async function students(schoolId = SCHOOL) {
  const snap = await db().collection(FirestorePaths.students(schoolId)).get();
  return snap.docs.map((d) => d.data());
}

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.applicants(schoolId),
    FirestorePaths.students(schoolId),
    FirestorePaths.auditLog(schoolId),
    FirestorePaths.programs(schoolId),
    `schools/${schoolId}/counters`,
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

/** Puts an applicant on file at [stage], bypassing the pipeline. */
async function seedApplicant(fields: Record<string, unknown> = {}, id = APPLICANT) {
  await db().doc(FirestorePaths.applicantDoc(SCHOOL, id)).set({
    id,
    schoolId: SCHOOL,
    referenceNumber: "A-2026-00001",
    ...enquiry,
    guardianEmail: null,
    email: null,
    phone: null,
    stage: "inquiry",
    studentId: null,
    isDeleted: false,
    ...fields,
  });
}

describe("the applicant flow", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const [save, advance, enrol] = await Promise.all([
      import("../../../src/callable/admissions/saveApplicant"),
      import("../../../src/callable/admissions/advanceApplicant"),
      import("../../../src/callable/admissions/enrolApplicant"),
    ]);
    callSave = fft.wrap(save.saveApplicant);
    callAdvance = fft.wrap(advance.advanceApplicant);
    callEnrol = fft.wrap(enrol.enrolApplicant);
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

  describe("taking down an enquiry", () => {
    it("creates one, with a reference number the client did not choose", async () => {
      const result = await callSave({
        data: {schoolId: SCHOOL, ...enquiry},
        auth: caller("registrar"),
      } as never);

      expect(result.applicantId).toBeTruthy();
      const doc = await applicantDoc(result.applicantId);
      expect(doc?.firstName).toBe("Bea");
      expect(doc?.stage).toBe("inquiry");
      expect(doc?.referenceNumber).toMatch(/^A-\d{4}-\d+$/);
    });

    it("refuses a number that could never be rung", async () => {
      // The field was mandatory and unchecked, so "0" satisfied it. The
      // reason it is mandatory at all is that somebody can be rung back.
      await expect(
        callSave({
          data: {schoolId: SCHOOL, ...enquiry, guardianPhone: "0"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/not a mobile number this system can read/);

      expect((await db().collection(FirestorePaths.applicants(SCHOOL)).get()).empty).toBe(true);
    });

    it("refuses an address that would later be copied onto a student", async () => {
      // Admissions was the back door around the student form's checks.
      await expect(
        callSave({
          data: {schoolId: SCHOOL, ...enquiry, guardianEmail: "alma@gmailcom"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/not a valid email address for the guardian/);
    });

    it("stores the applicant's own contact details, lower-cased", async () => {
      const result = await callSave({
        data: {
          schoolId: SCHOOL,
          ...enquiry,
          email: "Bea.Marquez@Student.School.edu.ph",
          phone: "+63 918 555 0100",
        },
        auth: caller("registrar"),
      } as never);

      const doc = await applicantDoc(result.applicantId);
      expect(doc?.email).toBe("bea.marquez@student.school.edu.ph");
      // The number stays as typed: the office reads it back to a family.
      expect(doc?.phone).toBe("+63 918 555 0100");
    });

    it("edits an existing enquiry without touching its stage", async () => {
      // An edit to a phone number and a decision to offer a place are
      // different acts. A save that could do both is one where a typo
      // moves a family through the pipeline.
      await seedApplicant({stage: "offered"});
      await callSave({
        data: {schoolId: SCHOOL, applicantId: APPLICANT, ...enquiry, guardianPhone: "09181112222"},
        auth: caller("registrar"),
      } as never);

      const doc = await applicantDoc();
      expect(doc?.guardianPhone).toBe("09181112222");
      expect(doc?.stage).toBe("offered");
    });

    it("refuses roles outside the admissions office", async () => {
      for (const role of ["faculty", "guidance", "staff", "student", "parent"]) {
        await expect(
          callSave({data: {schoolId: SCHOOL, ...enquiry}, auth: caller(role)} as never)
        ).rejects.toThrow(/requires one of the following roles/i);
      }
    });

    it("refuses a caller from another school", async () => {
      await expect(
        callSave({
          data: {schoolId: SCHOOL, ...enquiry},
          auth: caller("registrar", "registrar_elsewhere", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow();
    });
  });

  describe("moving through the pipeline", () => {
    it("moves one step and records when", async () => {
      await seedApplicant();
      await callAdvance({
        data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "applied"},
        auth: caller("registrar"),
      } as never);

      const doc = await applicantDoc();
      expect(doc?.stage).toBe("applied");
      expect(doc?.stageChangedAt).toBeDefined();
    });

    it("refuses a jump the pipeline does not allow", async () => {
      // Somebody marking a family as offered because that is the outcome
      // they expect. The funnel then reports offers the school never made.
      await seedApplicant();
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "offered"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow();
      expect((await applicantDoc())?.stage).toBe("inquiry");
    });

    it("will not let enrolment be reached by setting a stage", async () => {
      // The one stage with a student record behind it. A stage set to
      // "enrolled" on its own is an applicant the school believes is a
      // student and the registrar cannot find.
      await seedApplicant({stage: "reserved"});
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "enrolled"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow();

      expect((await applicantDoc())?.stage).toBe("reserved");
      expect(await students()).toHaveLength(0);
    });

    it("insists on the evidence each stage is named for", async () => {
      // No date, no "exam scheduled" -- it would say nothing anybody can
      // act on. No score, no "exam taken".
      await seedApplicant({stage: "applied"});
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "exam_scheduled"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/needs a date/);

      await seedApplicant({stage: "exam_scheduled"});
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "exam_taken"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow();
    });

    it("adds a second reservation payment rather than replacing the first", async () => {
      // A family paying in two instalments is ordinary. Overwriting would
      // lose money the school has taken and would then not credit at
      // enrolment.
      await seedApplicant({stage: "offered"});
      await callAdvance({
        data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "reserved", reservationFee: 2000},
        auth: caller("registrar"),
      } as never);
      expect((await applicantDoc())?.reservationFeePaid).toBe(2000);

      // Back a step and forward again, which is how a second payment is
      // taken on the same record.
      await callAdvance({
        data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "offered"},
        auth: caller("registrar"),
      } as never);
      await callAdvance({
        data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "reserved", reservationFee: 1500},
        auth: caller("registrar"),
      } as never);

      expect((await applicantDoc())?.reservationFeePaid).toBe(3500);
    });

    it("refuses an enquiry that is not on file", async () => {
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: "app_nobody", stage: "applied"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/not on file/);
    });

    it("refuses one that has been soft-deleted", async () => {
      await seedApplicant({isDeleted: true});
      await expect(
        callAdvance({
          data: {schoolId: SCHOOL, applicantId: APPLICANT, stage: "applied"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/not on file/);
    });
  });

  describe("enrolling", () => {
    const enrolData = {
      schoolId: SCHOOL,
      applicantId: APPLICANT,
      section: "Grade 7 - Mabini",
      birthDate: "2013-04-11",
    };

    it("creates the student and stamps the id back on the applicant", async () => {
      await seedApplicant({stage: "reserved"});
      const result = await callEnrol({data: enrolData, auth: caller("registrar")} as never);

      const roster = await students();
      expect(roster).toHaveLength(1);
      expect(roster[0].firstName).toBe("Bea");
      expect(roster[0].section).toBe("Grade 7 - Mabini");
      expect(roster[0].studentNumber).toBe(result.studentNumber);

      const doc = await applicantDoc();
      expect(doc?.stage).toBe("enrolled");
      expect(doc?.studentId).toBe(roster[0].id);
    });

    it("carries the family's contact details onto the student record", async () => {
      // The regression this test exists for. The student record grew an
      // email and a phone, and admissions -- the one path that had been
      // collecting them for weeks -- was writing neither. A student who
      // arrived this way could not be given a portal account at all,
      // because the Registrar screen refuses to create one against an
      // address nobody wrote down.
      await seedApplicant({
        stage: "reserved",
        email: "bea.marquez@student.school.edu.ph",
        phone: "0918 555 0100",
        guardianEmail: "alma@gmail.com",
      });
      await callEnrol({data: enrolData, auth: caller("registrar")} as never);

      const student = (await students())[0];
      expect(student.email).toBe("bea.marquez@student.school.edu.ph");
      expect(student.phone).toBe("0918 555 0100");
      expect(student.guardianContacts[0]).toMatchObject({
        name: "Alma Marquez",
        phone: "09171234567",
        email: "alma@gmail.com",
      });
    });

    it("writes null rather than undefined when the family gave neither", async () => {
      // A Grade 1 applicant has no email and no handset. The fields have
      // to read as "none on file", which is what the roster screens and
      // the provisioning gate both check.
      await seedApplicant({stage: "reserved"});
      await callEnrol({data: enrolData, auth: caller("registrar")} as never);

      const student = (await students())[0];
      expect(student.email).toBeNull();
      expect(student.phone).toBeNull();
    });

    it("credits a reservation fee as a negative balance", async () => {
      // Money the family has already handed over, against fees not yet
      // assessed. A positive number here would bill them for it twice.
      await seedApplicant({stage: "reserved", reservationFeePaid: 2500});
      await callEnrol({data: enrolData, auth: caller("registrar")} as never);

      expect((await students())[0].balance).toBe(-2500);
    });

    it("gives one family one student record when two clicks arrive at once", async () => {
      // The case the transaction exists for, and the reason this suite is
      // emulator-backed rather than mocked. Two records would mean two
      // ledgers and two report cards for one child, found in March.
      await seedApplicant({stage: "reserved"});

      const results = await Promise.allSettled(
        Array.from({length: 5}, () =>
          callEnrol({data: enrolData, auth: caller("registrar")} as never)
        )
      );

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      expect(await students()).toHaveLength(1);

      for (const rejected of results.filter((r) => r.status === "rejected")) {
        expect((rejected as PromiseRejectedResult).reason.message)
          .toMatch(/enrolled a moment ago|already/i);
      }
    });

    it("refuses to enrol the same applicant twice, later", async () => {
      await seedApplicant({stage: "reserved"});
      await callEnrol({data: enrolData, auth: caller("registrar")} as never);

      await expect(
        callEnrol({data: enrolData, auth: caller("registrar")} as never)
      ).rejects.toThrow();
      expect(await students()).toHaveLength(1);
    });

    it("insists on a section, because a student needs a class", async () => {
      await seedApplicant({stage: "reserved"});
      await expect(
        callEnrol({data: {...enrolData, section: "  "}, auth: caller("registrar")} as never)
      ).rejects.toThrow(/no section/i);
      expect(await students()).toHaveLength(0);
    });

    it("insists on a birthday, and refuses one in the future", async () => {
      await seedApplicant({stage: "reserved"});
      await expect(
        callEnrol({data: {...enrolData, birthDate: ""}, auth: caller("registrar")} as never)
      ).rejects.toThrow(/valid birthday/i);
      await expect(
        callEnrol({data: {...enrolData, birthDate: "2099-01-01"}, auth: caller("registrar")} as never)
      ).rejects.toThrow();
      expect(await students()).toHaveLength(0);
    });

    it("refuses a Senior High applicant with no strand", async () => {
      // The division has a catalogue, so a student in it without a strand
      // is a record every downstream rule has to special-case.
      await seedApplicant({
        stage: "reserved",
        educationLevel: "senior_high",
        gradeLevel: "Grade 11",
        programId: null,
      });
      await expect(
        callEnrol({data: enrolData, auth: caller("registrar")} as never)
      ).rejects.toThrow(/strand or program/i);
      expect(await students()).toHaveLength(0);
    });

    it("refuses roles outside the admissions office", async () => {
      await seedApplicant({stage: "reserved"});
      for (const role of ["faculty", "guidance", "parent"]) {
        await expect(
          callEnrol({data: enrolData, auth: caller(role)} as never)
        ).rejects.toThrow(/requires one of the following roles/i);
      }
      expect(await students()).toHaveLength(0);
    });
  });
});
