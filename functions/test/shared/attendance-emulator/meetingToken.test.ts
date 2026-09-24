/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/attendance-emulator"
 *
 * Who gets a pass into the lesson, and who does not.
 *
 * The token exists so nobody is asked to sign in to Jitsi -- they signed
 * in to LogicClass. That makes this callable the thing standing where
 * Jitsi's own sign-in used to, so it is tested as an access check rather
 * than as a token factory.
 */
import * as admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});
const SCHOOL = "school_token";
const SESSION = "2026-09-23_blk_math";
const OTHER_SESSION = "2026-09-23_blk_science";
const ROOM = "lc-abcdefghijklmnopqrst";
const OTHER_ROOM = "lc-zyxwvutsrqponmlkjihg";

/* eslint-disable @typescript-eslint/no-explicit-any */
let issueToken: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

function caller(role: string, uid = `${role}_1`, name = `${role} one`) {
  return {
    uid,
    token: {role, schoolId: SCHOOL, status: "active", mustChangePassword: false, name},
  };
}

function claimsOf(token: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
}

async function clear(path: string) {
  const snap = await db().collection(path).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

async function seed({room = ROOM as string | null} = {}) {
  await clear(FirestorePaths.classSessions(SCHOOL));
  await clear(FirestorePaths.subjectAttendance(SCHOOL));
  await clear(FirestorePaths.students(SCHOOL));

  for (const [id, subject, r] of [
    [SESSION, "Mathematics", room],
    [OTHER_SESSION, "Science", OTHER_ROOM],
  ] as [string, string, string | null][]) {
    await db().doc(FirestorePaths.classSessionDoc(SCHOOL, id)).set({
      id,
      schoolId: SCHOOL,
      subject,
      section: "Grade 10 - Rizal",
      teacherId: "faculty_1",
      teacherName: "faculty one",
      takenByUid: "faculty_1",
      date: "2026-09-23",
      status: "open",
      meetingRoom: r,
      deliveryMode: r ? "online" : "in_person",
      isDeleted: false,
    });
  }

  // The link from an account to a child is on the student record, not
  // on the user document -- which is why this is a callable.
  await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_1")).set({
    id: "stu_1",
    userId: "student_1",
    fullName: "Ana Cruz",
    section: "Grade 10 - Rizal",
    isDeleted: false,
  });
  await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_2")).set({
    id: "stu_2",
    userId: "student_2",
    fullName: "Ben Reyes",
    section: "Grade 9 - Mabini",
    isDeleted: false,
  });

  // Ana is on this register. Ben is not.
  await db()
    .doc(`${FirestorePaths.subjectAttendance(SCHOOL)}/${SESSION}_stu_1`)
    .set({
      id: `${SESSION}_stu_1`,
      sessionId: SESSION,
      studentId: "stu_1",
      studentName: "Ana Cruz",
      status: "present",
      meetingRoom: room,
      isDeleted: false,
    });
}

describe("the pass into a lesson", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    issueToken = fft.wrap(
      (await import("../../../src/callable/classSessions/issueMeetingToken")).issueMeetingToken
    );
  });

  afterAll(() => fft.cleanup());
  beforeEach(async () => {
    delete process.env.JITSI_APP_ID;
    delete process.env.JITSI_APP_SECRET;
    await seed();
  });

  describe("who may have one", () => {
    it("gives the teacher of the class the room, as moderator", async () => {
      process.env.JITSI_APP_ID = "logicclass";
      process.env.JITSI_APP_SECRET = "shhh";

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty", "faculty_1", "Ms Santos"),
      } as never);

      const claims = claimsOf(result.token);
      expect(claims.room).toBe(ROOM);
      const user = (claims.context as Record<string, Record<string, unknown>>).user;
      expect(user.moderator).toBe(true);
      expect(user.name).toBe("Ms Santos");
    });

    it("refuses another teacher's class", async () => {
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("faculty", "faculty_2"),
        } as never)
      ).rejects.toThrow(/Mathematics is faculty one's/);
    });

    it("lets an admin cover it", async () => {
      process.env.JITSI_APP_ID = "logicclass";
      process.env.JITSI_APP_SECRET = "shhh";

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("admin"),
      } as never);
      expect(claimsOf(result.token).room).toBe(ROOM);
    });

    it("gives a student on the register the room, not as moderator", async () => {
      process.env.JITSI_APP_ID = "logicclass";
      process.env.JITSI_APP_SECRET = "shhh";

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      const claims = claimsOf(result.token);
      expect(claims.room).toBe(ROOM);
      const user = (claims.context as Record<string, Record<string, unknown>>).user;
      // A child who can mute the teacher and end the lesson for the
      // class is a child who will.
      expect(user.moderator).toBe(false);
    });

    it("refuses a student who is not on that register", async () => {
      // The whole access rule, in one case: a child reaches a room
      // through their own line in the register and no other way.
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_2"),
        } as never)
      ).rejects.toThrow(/not in that class/);
    });

    it("refuses an account with no student record behind it", async () => {
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_nobody"),
        } as never)
      ).rejects.toThrow(/No student record/);
    });

    it("refuses another school outright", async () => {
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: {
            uid: "faculty_1",
            token: {role: "faculty", schoolId: "some_other_school", status: "active"},
          },
        } as never)
      ).rejects.toThrow(/do not have access/);
    });
  });

  describe("what it opens", () => {
    it("never carries a room the caller did not earn", async () => {
      process.env.JITSI_APP_ID = "logicclass";
      process.env.JITSI_APP_SECRET = "shhh";

      // Ana is on the Mathematics register and not the Science one.
      // Asking for Science must not hand her the Science room.
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: OTHER_SESSION},
          auth: caller("student", "student_1"),
        } as never)
      ).rejects.toThrow(/not in that class/);
    });

    it("refuses once the class comes back in person", async () => {
      // The door shutting, not a fault: setClassSessionMode clears the
      // room from the session and from every mark.
      await seed({room: null});
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("faculty", "faculty_1"),
        } as never)
      ).rejects.toThrow(/not online/);
    });

    it("refuses a room that did not come from this app", async () => {
      // A value that reached the document by some other route is not a
      // room this server generated, and signing a pass to it is signing
      // a pass to somewhere unknown.
      await seed({room: "https://evil.example.com/classroom"});
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("faculty", "faculty_1"),
        } as never)
      ).rejects.toThrow(/not online/);
    });
  });

  describe("a school that has configured no signing key", () => {
    it("gets no token and no error", async () => {
      // Still a lesson. It just joins the way it did before tokens
      // existed, which is right on a deployment that does not ask.
      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty", "faculty_1"),
      } as never);

      expect(result.token).toBeNull();
      expect(result.room).toBe(ROOM);
    });

    it("still refuses somebody who does not belong in the class", async () => {
      // The access check is not the token's job, and must not be
      // skipped along with it.
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_2"),
        } as never)
      ).rejects.toThrow(/not in that class/);
    });
  });

  it("keeps the room out of the audit log", async () => {
    process.env.JITSI_APP_ID = "logicclass";
    process.env.JITSI_APP_SECRET = "shhh";
    await clear(FirestorePaths.auditLog(SCHOOL));

    await issueToken({
      data: {schoolId: SCHOOL, sessionId: SESSION},
      auth: caller("faculty", "faculty_1"),
    } as never);

    // Every join would write a row naming a room, in a log the whole
    // office reads, and the room name is the whole of what keeps a
    // stranger out of a class of children.
    const log = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
    expect(log.size).toBe(0);
  });
});
