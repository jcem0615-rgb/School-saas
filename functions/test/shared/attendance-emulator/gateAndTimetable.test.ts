/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/attendance-emulator"
 *
 * The gate scanner and the timetable, against a real Firestore.
 *
 * Two defects are pinned here, and both were silent.
 *
 * The scanner read *any* second tap on the same day as a time out. A
 * queue at the gate produces two taps a few seconds apart, so the record
 * then said a person arrived at 07:02 and left at 07:02 -- and nothing
 * downstream flagged it, because `buildTimesheet` treats a day with both
 * stamps as complete. For an hourly employee that is a day's pay.
 *
 * The timetable ignored `term`, which the block itself documented as
 * being "for schools whose timetable changes partway through the year".
 * Two blocks in different semesters never coexist, so calling them a
 * clash made the second semester impossible to enter.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_gate";
const STUDENT_UID = "u_student_1";
const STUDENT_ID = "stu_1";
const QR = "qr-token-student-1";
const SECTION = "STEM 11-A";

/* eslint-disable @typescript-eslint/no-explicit-any */
let callMark: any;
let callSaveBlock: any;
let callOpenSession: any;
let callMarkSubject: any;
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

async function wipe() {
  for (const path of [
    FirestorePaths.users(SCHOOL),
    FirestorePaths.students(SCHOOL),
    FirestorePaths.attendance(SCHOOL),
    FirestorePaths.scheduleBlocks(SCHOOL),
    FirestorePaths.classSessions(SCHOOL),
    FirestorePaths.subjectAttendance(SCHOOL),
    FirestorePaths.auditLog(SCHOOL),
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await db().doc(FirestorePaths.platformSchoolDoc(SCHOOL)).delete();
}

async function seed() {
  await wipe();
  await db().doc(FirestorePaths.platformSchoolDoc(SCHOOL)).set({
    schoolId: SCHOOL,
    timezone: "Asia/Manila",
  });
  await db().doc(FirestorePaths.userDoc(SCHOOL, STUDENT_UID)).set({
    id: STUDENT_UID,
    schoolId: SCHOOL,
    role: "student",
    status: "active",
    firstName: "Miguel",
    lastName: "Torres",
    qrCode: QR,
    isDeleted: false,
  });
  await db().doc(FirestorePaths.studentDoc(SCHOOL, STUDENT_ID)).set({
    id: STUDENT_ID,
    schoolId: SCHOOL,
    userId: STUDENT_UID,
    firstName: "Miguel",
    lastName: "Torres",
    section: SECTION,
    status: "enrolled",
    isDeleted: false,
  });
}

/** Monday = 1 .. Sunday = 7, at the school rather than at the server. */
function manilaWeekday(): number {
  const key = new Intl.DateTimeFormat("en-CA", {timeZone: "Asia/Manila"}).format(new Date());
  const [y, m, d] = key.split("-").map(Number);
  const day = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return day === 0 ? 7 : day;
}

async function attendanceRows() {
  const snap = await db().collection(FirestorePaths.attendance(SCHOOL)).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()} as Record<string, unknown>));
}

const block = (over: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  subject: "Mathematics",
  section: SECTION,
  teacherId: "t_1",
  teacherName: "Maria Santos",
  room: "Room 204",
  dayOfWeek: 1,
  startMinute: 7 * 60 + 30,
  endMinute: 8 * 60 + 30,
  schoolYear: "2026-2027",
  ...over,
});

describe("the gate and the timetable", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const [m, s, o, ms] = await Promise.all([
      import("../../../src/callable/attendance/markAttendance"),
      import("../../../src/callable/schedule/saveScheduleBlock"),
      import("../../../src/callable/classSessions/openClassSession"),
      import("../../../src/callable/classSessions/markSubjectAttendance"),
    ]);
    callMark = fft.wrap(m.markAttendance);
    callSaveBlock = fft.wrap(s.saveScheduleBlock);
    callOpenSession = fft.wrap(o.openClassSession);
    callMarkSubject = fft.wrap(ms.markSubjectAttendance);
  });

  afterAll(async () => {
    await wipe();
    fft.cleanup();
  });

  beforeEach(seed);

  describe("a second tap at the gate", () => {
    it("does not sign somebody out seconds after signing them in", async () => {
      // The defect. Two taps in the queue used to produce a day that
      // began and ended in the same minute.
      const first = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(first.action).toBe("time_in");

      const second = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(second.action).toBe("too_soon");

      const rows = await attendanceRows();
      expect(rows).toHaveLength(1);
      // Still open. A day with both stamps filled in is a day the
      // timesheet believes, and this one is not finished.
      expect(rows[0].timestampOut).toBeNull();
    });

    it("says how long the window is, so the scanner can explain itself", async () => {
      const result = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(result.minimumDwellMinutes).toBe(5);
    });

    it("still signs them out once they have actually been in", async () => {
      await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      // Wind the arrival back, which is what a real day does.
      const rows = await attendanceRows();
      await db()
        .doc(FirestorePaths.attendanceDoc(SCHOOL, rows[0].id as string))
        .update({
          timestampIn: admin.firestore.Timestamp.fromMillis(Date.now() - 6 * 60 * 60 * 1000),
        });

      const out = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(out.action).toBe("time_out");
      expect((await attendanceRows())[0].timestampOut).not.toBeNull();
    });

    it("does not reopen a day that is already finished", async () => {
      await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      const rows = await attendanceRows();
      await db()
        .doc(FirestorePaths.attendanceDoc(SCHOOL, rows[0].id as string))
        .update({
          timestampIn: admin.firestore.Timestamp.fromMillis(Date.now() - 6 * 60 * 60 * 1000),
        });
      await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);

      const third = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(third.action).toBe("already_completed");
    });

    it("files the day under the school's date, not the server's", async () => {
      // A class scanned at 8am in Manila is the previous evening in UTC.
      // A key taken from the server clock puts every early scan on
      // yesterday, which is a register saying a child came twice on
      // Tuesday and never on Wednesday.
      const result = await callMark({data: {qrToken: QR}, auth: caller("faculty")} as never);
      expect(result.action).toBe("time_in");
      const manilaToday = new Intl.DateTimeFormat("en-CA", {
        timeZone: "Asia/Manila",
      }).format(new Date());
      expect((await attendanceRows())[0].date).toBe(manilaToday);
    });
  });

  describe("two timetables in one school year", () => {
    it("lets the same slot be used again in the other semester", async () => {
      // Same teacher, same section, same room, same slot -- and no
      // clash, because the two are never in the same week. Before this,
      // a school could not enter its second semester at all.
      const first = await callSaveBlock({
        data: block({term: "1st Semester"}),
        auth: caller("admin"),
      } as never);
      expect(first.blockId).toBeTruthy();

      const second = await callSaveBlock({
        data: block({term: "2nd Semester", subject: "Physics"}),
        auth: caller("admin"),
      } as never);
      expect(second.blockId).toBeTruthy();

      const snap = await db().collection(FirestorePaths.scheduleBlocks(SCHOOL)).get();
      expect(snap.docs).toHaveLength(2);
    });

    it("still refuses a real double-booking inside one semester", async () => {
      await callSaveBlock({
        data: block({term: "1st Semester"}),
        auth: caller("admin"),
      } as never);
      await expect(
        callSaveBlock({
          data: block({term: "1st Semester", subject: "Physics"}),
          auth: caller("admin"),
        } as never)
      ).rejects.toThrow(/already/i);
    });

    it("names the semester in the refusal", async () => {
      await callSaveBlock({
        data: block({term: "1st Semester"}),
        auth: caller("admin"),
      } as never);
      await expect(
        callSaveBlock({
          data: block({term: "1st Semester", subject: "Physics"}),
          auth: caller("admin"),
        } as never)
      ).rejects.toThrow(/1st Semester/);
    });

    it("treats an all-year class as being there in every semester", async () => {
      // A Grade 7 class genuinely is in the room both semesters, so a
      // semester class landing on it has to be refused.
      await callSaveBlock({data: block(), auth: caller("admin")} as never);
      await expect(
        callSaveBlock({
          data: block({term: "2nd Semester", subject: "Physics"}),
          auth: caller("admin"),
        } as never)
      ).rejects.toThrow(/already/i);
    });

    it("stores the term it was saved with", async () => {
      const {blockId} = await callSaveBlock({
        data: block({term: " 1st Semester "}),
        auth: caller("admin"),
      } as never);
      const snap = await db().doc(FirestorePaths.scheduleBlockDoc(SCHOOL, blockId)).get();
      expect(snap.data()!.term).toBe("1st Semester");
    });

    it("reads a blank term as all year rather than as a term called nothing", async () => {
      const {blockId} = await callSaveBlock({
        data: block({term: "   "}),
        auth: caller("admin"),
      } as never);
      const snap = await db().doc(FirestorePaths.scheduleBlockDoc(SCHOOL, blockId)).get();
      expect(snap.data()!.term).toBeNull();
    });
  });

  describe("a student marked late halfway through the lesson", () => {
    /** Opens today's class and returns the session and the student's mark. */
    async function openToday() {
      const {blockId} = await callSaveBlock({
        data: block({dayOfWeek: manilaWeekday()}),
        auth: caller("admin", "t_1"),
      } as never);
      const opened = await callOpenSession({
        data: {schoolId: SCHOOL, scheduleBlockId: blockId},
        auth: caller("faculty", "t_1"),
      } as never);
      return opened.sessionId as string;
    }

    async function markOf(sessionId: string) {
      const snap = await db()
        .doc(FirestorePaths.subjectAttendanceDoc(SCHOOL, `${sessionId}_${STUDENT_ID}`))
        .get();
      return snap.data()!;
    }

    it("is recorded as arriving when the teacher said so, not on the bell", async () => {
      // The defect. Opening a session stamps every student on the roll
      // with the session's own open time, and the mark used to keep
      // whatever was already there -- so a student switched to late kept
      // the bell time, which is the one thing "late" says they missed.
      const sessionId = await openToday();
      const openedAt = (await markOf(sessionId)).timeIn as admin.firestore.Timestamp;

      // Wind the class back an hour, the way a real lesson runs on.
      await db()
        .doc(FirestorePaths.classSessionDoc(SCHOOL, sessionId))
        .update({openedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000)});

      await callMarkSubject({
        data: {schoolId: SCHOOL, sessionId, studentId: STUDENT_ID, status: "late"},
        auth: caller("faculty", "t_1"),
      } as never);

      const after = await markOf(sessionId);
      const timeIn = after.timeIn as admin.firestore.Timestamp;
      expect(after.status).toBe("late");
      expect(timeIn.toMillis()).toBeGreaterThan(openedAt.toMillis());
    });

    it("goes back to the bell when the teacher corrects it to present", async () => {
      const sessionId = await openToday();
      const openedAt = admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
      await db()
        .doc(FirestorePaths.classSessionDoc(SCHOOL, sessionId))
        .update({openedAt});

      await callMarkSubject({
        data: {schoolId: SCHOOL, sessionId, studentId: STUDENT_ID, status: "late"},
        auth: caller("faculty", "t_1"),
      } as never);
      await callMarkSubject({
        data: {schoolId: SCHOOL, sessionId, studentId: STUDENT_ID, status: "present"},
        auth: caller("faculty", "t_1"),
      } as never);

      const timeIn = (await markOf(sessionId)).timeIn as admin.firestore.Timestamp;
      // Present means they were here when it started, so that is the
      // time the row carries -- a mis-tap does not leave a child
      // permanently recorded as having walked in late.
      expect(timeIn.toMillis()).toBe(openedAt.toMillis());
    });

    it("keeps no arrival time for a student marked absent", async () => {
      const sessionId = await openToday();
      await callMarkSubject({
        data: {schoolId: SCHOOL, sessionId, studentId: STUDENT_ID, status: "absent"},
        auth: caller("faculty", "t_1"),
      } as never);
      expect((await markOf(sessionId)).timeIn).toBeNull();
    });
  });
});
