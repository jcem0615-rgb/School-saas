/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/attendance-emulator"
 *
 * Taking today's lesson online, and shutting the door afterwards.
 *
 * The room name is the only thing that gets a person into a Jitsi room,
 * so most of what is pinned here is about where that name is allowed to
 * be and when it stops existing.
 */
import * as admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import {FirestorePaths} from "../../../src/shared/firestore-paths";
import {isMeetingRoom} from "../../../src/shared/meeting/room";

const fft = functionsTest({projectId: "school-saas-test"});
const SCHOOL = "school_online";
const SESSION = "2026-09-23_blk_math";

/* eslint-disable @typescript-eslint/no-explicit-any */
let setMode: any;
let closeSession: any;
let openSession: any;
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

async function clear(path: string) {
  const snap = await db().collection(path).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

async function session() {
  const doc = await db().doc(FirestorePaths.classSessionDoc(SCHOOL, SESSION)).get();
  return doc.data()!;
}

async function markRooms(): Promise<unknown[]> {
  const snap = await db()
    .collection(FirestorePaths.subjectAttendance(SCHOOL))
    .where("sessionId", "==", SESSION)
    .get();
  return snap.docs.map((d) => d.data().meetingRoom ?? null);
}

async function seed({status = "open"} = {}) {
  await clear(FirestorePaths.classSessions(SCHOOL));
  await clear(FirestorePaths.subjectAttendance(SCHOOL));
  await clear(FirestorePaths.auditLog(SCHOOL));

  await db().doc(FirestorePaths.classSessionDoc(SCHOOL, SESSION)).set({
    id: SESSION,
    schoolId: SCHOOL,
    scheduleBlockId: "blk_math",
    subject: "Mathematics",
    section: "Grade 10 - Rizal",
    teacherId: "faculty_1",
    teacherName: "faculty one",
    takenByUid: "faculty_1",
    takenByName: "faculty one",
    date: "2026-09-23",
    status,
    openedAt: admin.firestore.Timestamp.now(),
    closedAt: null,
    studentCount: 3,
    isDeleted: false,
  });

  // Three on the roll, one of them absent -- the absent one matters for
  // the clearing rule.
  const roll = [
    {id: "stu_1", status: "present"},
    {id: "stu_2", status: "present"},
    {id: "stu_3", status: "absent"},
  ];
  await Promise.all(
    roll.map((s) =>
      db().doc(`${FirestorePaths.subjectAttendance(SCHOOL)}/${SESSION}_${s.id}`).set({
        id: `${SESSION}_${s.id}`,
        sessionId: SESSION,
        studentId: s.id,
        studentName: s.id,
        subject: "Mathematics",
        section: "Grade 10 - Rizal",
        date: "2026-09-23",
        status: s.status,
        isDeleted: false,
      })
    )
  );
}

/** A block on a day that is not today, and a roll to open against it. */
async function seedOffTimetableBlock() {
  const notToday = ((new Date().getDay() + 3) % 7) || 7;
  await db().doc(FirestorePaths.scheduleBlockDoc(SCHOOL, "blk_makeup")).set({
    id: "blk_makeup",
    schoolId: SCHOOL,
    subject: "Mathematics",
    section: "Grade 10 - Rizal",
    teacherId: "faculty_1",
    teacherName: "faculty one",
    room: "Room 201",
    dayOfWeek: notToday,
    startMinute: 8 * 60,
    endMinute: 9 * 60,
    schoolYear: "2026-2027",
    isDeleted: false,
  });
  await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_makeup")).set({
    id: "stu_makeup",
    firstName: "Ana",
    lastName: "Cruz",
    section: "Grade 10 - Rizal",
    status: "enrolled",
    isDeleted: false,
  });
}

describe("taking a lesson online", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    setMode = fft.wrap(
      (await import("../../../src/callable/classSessions/setClassSessionMode")).setClassSessionMode
    );
    closeSession = fft.wrap(
      (await import("../../../src/callable/classSessions/closeClassSession")).closeClassSession
    );
    openSession = fft.wrap(
      (await import("../../../src/callable/classSessions/openClassSession")).openClassSession
    );
  });

  afterAll(() => fft.cleanup());
  beforeEach(() => seed());

  describe("a lesson the timetable does not put today", () => {
    beforeEach(seedOffTimetableBlock);

    it("is refused when nobody asked for it deliberately", async () => {
      // The day's list keeps the guard it has always had: a stale
      // screen, or a phone that slept through midnight, must not file a
      // day's marks against a class that is not running.
      await expect(
        openSession({
          data: {schoolId: SCHOOL, scheduleBlockId: "blk_makeup"},
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/not timetabled today/);
    });

    it("is held when the teacher means it", async () => {
      // A make-up for the day a typhoon closed the school, a review
      // session before an exam. The lessons most worth holding online
      // are the ones no timetable has a row for, and refusing them
      // means the feature works on the days it is least needed.
      const result = await openSession({
        data: {schoolId: SCHOOL, scheduleBlockId: "blk_makeup", unscheduled: true},
        auth: caller("faculty"),
      } as never);

      expect(result.sessionId).toBeTruthy();
      const doc = await db()
        .doc(FirestorePaths.classSessionDoc(SCHOOL, result.sessionId))
        .get();
      expect(doc.data()!.status).toBe("open");
      // Filed under the day it actually happened, not the day the
      // timetable gives the class.
      expect(doc.data()!.date).toBe(new Date().toISOString().slice(0, 10));
    });

    it("says on the register that it was not on the timetable", async () => {
      // "Why is there a Mathematics register dated a Sunday" is asked
      // of the record months later, by somebody who cannot ask the
      // teacher.
      const result = await openSession({
        data: {schoolId: SCHOOL, scheduleBlockId: "blk_makeup", unscheduled: true},
        auth: caller("faculty"),
      } as never);

      const doc = await db()
        .doc(FirestorePaths.classSessionDoc(SCHOOL, result.sessionId))
        .get();
      expect(doc.data()!.unscheduled).toBe(true);
    });

    it("leaves an ordinary register saying nothing of the kind", async () => {
      const result = await openSession({
        data: {schoolId: SCHOOL, scheduleBlockId: "blk_makeup", unscheduled: true},
        auth: caller("faculty"),
      } as never);
      expect(result.sessionId).toBeTruthy();

      // Same class, on its own day, is an ordinary lesson.
      await db().doc(FirestorePaths.scheduleBlockDoc(SCHOOL, "blk_today")).set({
        id: "blk_today",
        schoolId: SCHOOL,
        subject: "Science",
        section: "Grade 10 - Rizal",
        teacherId: "faculty_1",
        teacherName: "faculty one",
        dayOfWeek: new Date().getDay() === 0 ? 7 : new Date().getDay(),
        startMinute: 10 * 60,
        endMinute: 11 * 60,
        schoolYear: "2026-2027",
        isDeleted: false,
      });
      const ordinary = await openSession({
        data: {schoolId: SCHOOL, scheduleBlockId: "blk_today"},
        auth: caller("faculty"),
      } as never);
      const doc = await db()
        .doc(FirestorePaths.classSessionDoc(SCHOOL, ordinary.sessionId))
        .get();
      expect(doc.data()!.unscheduled).toBe(false);
    });

    it("still refuses another teacher's class", async () => {
      // Stepping around the timetable is not stepping around whose
      // class it is.
      await expect(
        openSession({
          data: {schoolId: SCHOOL, scheduleBlockId: "blk_makeup", unscheduled: true},
          auth: caller("faculty", "faculty_2"),
        } as never)
      ).rejects.toThrow(/faculty one's/);
    });
  });

  describe("opening the room", () => {
    it("gives the class a room nobody could have guessed", async () => {
      const result = await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);

      expect(isMeetingRoom(result.meetingRoom)).toBe(true);
      expect((await session()).deliveryMode).toBe("online");
    });

    it("puts it on every student's own line, and only there", async () => {
      // classSessions is staff-only, so the room reaches a student
      // through the one document in this collection that is theirs.
      // No rule had to be widened to let a class be joined.
      const result = await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);

      const rooms = await markRooms();
      expect(rooms).toHaveLength(3);
      expect(new Set(rooms)).toEqual(new Set([result.meetingRoom]));
      expect(result.studentsReached).toBe(3);
    });

    it("gives a different room each time it is taken online", async () => {
      const first = await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);
      const second = await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);

      expect(second.meetingRoom).not.toBe(first.meetingRoom);
      // And the old one is gone from the marks, so a link copied a
      // minute ago is not still live.
      expect(new Set(await markRooms())).toEqual(new Set([second.meetingRoom]));
    });

    it("does not write the room into the audit log", async () => {
      // The log is read school-wide. The room name is the secret that
      // gets into the class, so copying it there would hand every
      // account in the office a way into any lesson.
      await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);

      const log = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
      expect(log.size).toBe(1);
      expect(JSON.stringify(log.docs[0].data())).not.toContain("lc-");
    });
  });

  describe("shutting the door", () => {
    it("brings the class back in person and takes the room off every mark",
      async () => {
        await setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty"),
        } as never);

        await setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "in_person"},
          auth: caller("faculty"),
        } as never);

        expect((await session()).meetingRoom).toBeNull();
        expect(await markRooms()).toEqual([null, null, null]);
      });

    it("closes the room when the teacher presses Time Out", async () => {
      // The defect this pins: without it the lesson ends, the teacher
      // leaves, and a class of children is in an unsupervised video call
      // reachable from a register that says the class is over.
      await setMode({
        data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
        auth: caller("faculty"),
      } as never);

      await closeSession({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty"),
      } as never);

      expect((await session()).meetingRoom).toBeNull();
      expect(await markRooms()).toEqual([null, null, null]);
    });

    it("including the absent student's, who was never in the lesson",
      async () => {
        // A child who was not there must not be left holding the way in
        // either. Time Out writes no timeOut for them, which is why this
        // is worth checking separately.
        await setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty"),
        } as never);
        await closeSession({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("faculty"),
        } as never);

        const absent = await db()
          .doc(`${FirestorePaths.subjectAttendance(SCHOOL)}/${SESSION}_stu_3`)
          .get();
        expect(absent.data()!.meetingRoom).toBeNull();
        expect(absent.data()!.timeOut).toBeUndefined();
      });

    it("refuses to open a room on a class that already finished", async () => {
      await seed({status: "closed"});
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/already finished/i);
    });
  });

  describe("who may do it", () => {
    it("is the teacher taking the class", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty"),
        } as never)
      ).resolves.toBeTruthy();
    });

    it("and the Admin, who covers", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("admin"),
        } as never)
      ).resolves.toBeTruthy();
    });

    it("but not another teacher's class", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty", "faculty_someone_else"),
        } as never)
      ).rejects.toThrow(/faculty one/);
      expect(await markRooms()).toEqual([null, null, null]);
    });

    it("and never a student, whatever else is true", async () => {
      // The one-way boundary the register already draws: a compromised
      // student device must not be able to open a room in a teacher's
      // name and invite whoever it likes.
      for (const role of ["student", "parent", "staff", "registrar", "guidance",
        "director", "principal"]) {
        await expect(
          setMode({
            data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
            auth: caller(role),
          } as never)
        ).rejects.toThrow(/role/i);
      }
      expect(await markRooms()).toEqual([null, null, null]);
    });

    it("and not a teacher at another school", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"},
          auth: caller("faculty", "faculty_b", "school_elsewhere"),
        } as never)
      ).rejects.toThrow(/access/i);
    });

    it("and not somebody signed out", async () => {
      await expect(
        setMode({data: {schoolId: SCHOOL, sessionId: SESSION, mode: "online"}} as never)
      ).rejects.toThrow(/signed in/i);
    });
  });

  describe("what it refuses to be asked", () => {
    it("a mode that is neither", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: SESSION, mode: "hybrid"},
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/online or in person/i);
    });

    it("a class that was never started", async () => {
      await expect(
        setMode({
          data: {schoolId: SCHOOL, sessionId: "2026-09-23_blk_nothing", mode: "online"},
          auth: caller("faculty"),
        } as never)
      ).rejects.toThrow(/not been started/i);
    });
  });
});
