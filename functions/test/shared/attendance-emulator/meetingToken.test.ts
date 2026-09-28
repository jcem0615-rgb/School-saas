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

const PASSCODE = "A1B2C3D4";

async function seed({
  room = ROOM as string | null,
  passcode = null as string | null,
  scope = undefined as Record<string, string[]> | undefined,
} = {}) {
  await clear(FirestorePaths.classSessions(SCHOOL));
  await clear(FirestorePaths.subjectAttendance(SCHOOL));
  await clear(FirestorePaths.students(SCHOOL));
  await clear(`schools/${SCHOOL}/meetingAttempts`);

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
      meetingPasscode: r ? passcode : null,
      scope: scope ?? null,
      deliveryMode: r ? "online" : "in_person",
      isDeleted: false,
    });
  }

  // The link from an account to a child is on the student record, not
  // on the user document -- which is why this is a callable.
  await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_1")).set({
    id: "stu_1",
    schoolId: SCHOOL,
    userId: "student_1",
    fullName: "Ana Cruz",
    status: "enrolled",
    section: "Grade 10 - Rizal",
    gradeLevel: "10",
    department: "Junior High School",
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
    delete process.env.LIVEKIT_URL;
    delete process.env.LIVEKIT_API_KEY;
    delete process.env.LIVEKIT_API_SECRET;
    await seed();
  });

  /** A school that has connected a media server. */
  function withMediaServer() {
    process.env.LIVEKIT_URL = "wss://school.livekit.cloud";
    process.env.LIVEKIT_API_KEY = "APIabc123";
    process.env.LIVEKIT_API_SECRET = "shhh";
  }

  describe("who may have one", () => {
    it("gives the teacher of the class the room, as moderator", async () => {
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty", "faculty_1", "Ms Santos"),
      } as never);

      expect(result.provider).toBe("livekit");
      expect(result.url).toBe("wss://school.livekit.cloud");
      const claims = claimsOf(result.token);
      const video = claims.video as Record<string, unknown>;
      expect(video.room).toBe(ROOM);
      expect(video.roomJoin).toBe(true);
      // The teacher can remove somebody from the lesson.
      expect(video.roomAdmin).toBe(true);
      expect(claims.name).toBe("Ms Santos");
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
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("admin"),
      } as never);
      const video = claimsOf(result.token).video as Record<string, unknown>;
      expect(video.room).toBe(ROOM);
    });

    it("gives a student on the register the room, not as moderator", async () => {
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      const claims = claimsOf(result.token);
      const video = claims.video as Record<string, unknown>;
      expect(video.room).toBe(ROOM);
      // A child who can remove the teacher from the lesson is a child
      // who will.
      expect(video.roomAdmin).toBe(false);
      expect(claims.name).toBe("Ana Cruz");
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
      withMediaServer();

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

  describe("a school that has connected no media server", () => {
    it("gets no token and no error", async () => {
      // The screens say so plainly rather than sending a class at
      // something that cannot work, which is what the embedded
      // fallback did until it was removed.
      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty", "faculty_1"),
      } as never);

      expect(result.provider).toBe("none");
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
    withMediaServer();
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

  // The link is an address, not a permission: it gets forwarded into a
  // group chat and screenshotted. So everything that decides who comes
  // in is here, and this is the part of it that a leaked link reaches.
  describe("the code the teacher reads out", () => {
    it("is not asked of the teacher, who set it", async () => {
      // A teacher locked out of their own lesson by their own code is a
      // lesson that does not happen.
      await seed({passcode: PASSCODE});
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("faculty", "faculty_1", "Ms Santos"),
      } as never);

      expect(result.room).toBe(ROOM);
    });

    it("stops a child on the register who does not have it", async () => {
      // The register says whether a child is in this class. It cannot
      // say whether the child is the one holding the phone, and in a
      // school it often is not.
      await seed({passcode: PASSCODE});
      withMediaServer();

      for (const attempt of [undefined, "", "ZZZZ9999", "A1B2C3D"]) {
        await expect(
          issueToken({
            data: {schoolId: SCHOOL, sessionId: SESSION, passcode: attempt},
            auth: caller("student", "student_1", "Ana Cruz"),
          } as never)
        ).rejects.toThrow(/not the code/i);
      }
    });

    it("lets that same child in once they have it", async () => {
      await seed({passcode: PASSCODE});
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      expect(result.room).toBe(ROOM);
    });

    it("forgives the dash it was shown with and the shift key", async () => {
      await seed({passcode: PASSCODE});
      withMediaServer();

      for (const typed of ["a1b2-c3d4", "  A1B2 C3D4 ", "A1B2-C3D4"]) {
        const result = await issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION, passcode: typed},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never);
        expect(result.room).toBe(ROOM);
      }
    });

    it("is not required by a lesson that has none", async () => {
      // Sessions opened before codes existed. Their lessons still have
      // to be joinable by the children on their registers.
      await seed({passcode: null});
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      expect(result.room).toBe(ROOM);
    });

    it("never comes back in the answer, right or wrong", async () => {
      // A refusal that quoted the code would be a refusal that handed
      // it over.
      await seed({passcode: PASSCODE});
      withMediaServer();

      const allowed = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);
      expect(JSON.stringify(allowed)).not.toContain(PASSCODE);

      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION, passcode: "WRONG999"},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(expect.not.stringContaining(PASSCODE) as never);
    });
  });

  describe("standing at the door trying codes", () => {
    async function guess(times: number, uid = "student_1") {
      for (let i = 0; i < times; i++) {
        await expect(
          issueToken({
            data: {schoolId: SCHOOL, sessionId: SESSION, passcode: `WRONG${i}99`},
            auth: caller("student", uid, "Ana Cruz"),
          } as never)
        ).rejects.toThrow();
      }
    }

    it("stops answering after eight wrong ones", async () => {
      await seed({passcode: PASSCODE});
      withMediaServer();

      await guess(8);

      // Even the right code, now. A door that will answer for ever is
      // worth standing at.
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/too many wrong codes/i);
    });

    it("forgets the wrong ones once the right one arrives", async () => {
      // Otherwise a child who mistyped it seven times this morning
      // starts the afternoon one keystroke from being locked out.
      await seed({passcode: PASSCODE});
      withMediaServer();

      await guess(7);
      await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);
      await guess(7);

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);
      expect(result.room).toBe(ROOM);
    });

    it("locks the guesser out and not the lesson", async () => {
      // Counted per person. Locking the lesson would hand any pupil in
      // the class a way to shut the rest of them out of it.
      await seed({passcode: PASSCODE});
      withMediaServer();
      await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_3")).set({
        id: "stu_3",
        schoolId: SCHOOL,
        userId: "student_3",
        fullName: "Cara Lim",
        status: "enrolled",
        section: "Grade 10 - Rizal",
        gradeLevel: "10",
        department: "Junior High School",
        isDeleted: false,
      });
      await db()
        .doc(`${FirestorePaths.subjectAttendance(SCHOOL)}/${SESSION}_stu_3`)
        .set({
          id: `${SESSION}_stu_3`,
          sessionId: SESSION,
          studentId: "stu_3",
          studentName: "Cara Lim",
          status: "present",
          meetingRoom: ROOM,
          isDeleted: false,
        });

      await guess(8, "student_1");

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
        auth: caller("student", "student_3", "Cara Lim"),
      } as never);
      expect(result.room).toBe(ROOM);
    });

    it("counts nothing for a lesson with no code", async () => {
      await seed({passcode: null});
      withMediaServer();

      for (let i = 0; i < 12; i++) {
        await issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION, passcode: "irrelevant"},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never);
      }

      const snap = await db().collection(`schools/${SCHOOL}/meetingAttempts`).get();
      expect(snap.empty).toBe(true);
    });
  });

  // The fourth lock. The first three can all be true of somebody who
  // has since moved: a register is a photograph of the roll when the
  // lesson opened, and a child can be in another section by the
  // afternoon with their mark still pointing at this morning.
  describe("where the child belongs now", () => {
    const scope = {
      section: ["Grade 10 - Rizal"],
      gradeLevel: ["10"],
      department: ["Junior High School"],
    };

    async function moveAna(fields: Record<string, string>) {
      await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_1")).update(fields);
    }

    it("lets in the child the lesson was opened for", async () => {
      await seed({scope});
      withMediaServer();

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      expect(result.room).toBe(ROOM);
    });

    it("refuses one moved to another section, mark and all", async () => {
      await seed({scope});
      withMediaServer();
      await moveAna({section: "Grade 10 - Bonifacio"});

      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/another section/i);
    });

    it("refuses one promoted out of the grade, or moved department", async () => {
      await seed({scope});
      withMediaServer();

      await moveAna({gradeLevel: "11"});
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/another grade level/i);

      await moveAna({gradeLevel: "10", department: "Senior High School"});
      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/another department/i);
    });

    it("refuses one who is no longer enrolled", async () => {
      await seed({scope});
      withMediaServer();
      await moveAna({status: "transferred"});

      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/no longer enrolled/i);
    });

    it("does not lock a school out of a lesson it opened before this", async () => {
      // Sessions with no scope on them. The register and the code still
      // decide; this simply has nothing to add.
      await seed({scope: undefined});
      withMediaServer();
      await moveAna({gradeLevel: "11", department: "Senior High School"});

      const result = await issueToken({
        data: {schoolId: SCHOOL, sessionId: SESSION},
        auth: caller("student", "student_1", "Ana Cruz"),
      } as never);

      expect(result.room).toBe(ROOM);
    });

    it("is checked before the code, so a stranger learns nothing", async () => {
      // Somebody who does not belong here should be told they do not
      // belong here, not invited to guess a code first.
      await seed({passcode: PASSCODE, scope});
      withMediaServer();
      await db()
        .doc(FirestorePaths.studentDoc(SCHOOL, "stu_1"))
        .update({section: "Grade 10 - Bonifacio"});

      await expect(
        issueToken({
          data: {schoolId: SCHOOL, sessionId: SESSION, passcode: PASSCODE},
          auth: caller("student", "student_1", "Ana Cruz"),
        } as never)
      ).rejects.toThrow(/another section/i);
    });
  });

});
