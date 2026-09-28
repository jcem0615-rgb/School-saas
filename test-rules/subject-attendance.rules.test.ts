import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * Per-subject attendance.
 *
 * The register a grade gets argued over. Everything in both collections
 * is written by a callable running with the Admin SDK; the point of
 * these tests is that no client can write either, and that reading a
 * child's marks is limited to the child, their parents, and the staff
 * who need them.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_subject_attendance";
const LAPSED = "school_subject_attendance_lapsed";

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "school-saas-test",
    firestore: {rules: fs.readFileSync("firestore.rules", "utf8")},
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function contextAs(role: string, uid: string, schoolId = SCHOOL) {
  return testEnv.authenticatedContext(uid, {
    schoolId,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const SESSION = "2026-03-03_blk_physics";
const MARK = `${SESSION}_stu_a`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [id, status] of [
      [SCHOOL, "active"],
      [LAPSED, "suspended"],
    ]) {
      await setDoc(doc(db, `platform_subscriptions/${id}`), {
        schoolId: id,
        currentStatus: status,
      });
    }
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_a`), {
      firstName: "Ana",
      lastName: "Cruz",
      section: "Grade 10 - Rizal",
      status: "enrolled",
      userId: "student_a",
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_a`), {
      role: "parent",
      status: "active",
      linkedStudentIds: ["stu_a"],
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_b`), {
      role: "parent",
      status: "active",
      linkedStudentIds: ["stu_z"],
    });
    await setDoc(doc(db, `schools/${SCHOOL}/classSessions/${SESSION}`), {
      id: SESSION,
      scheduleBlockId: "blk_physics",
      subject: "Physics",
      section: "Grade 10 - Rizal",
      teacherId: "teacher_a",
      takenByUid: "teacher_a",
      date: "2026-03-03",
      status: "open",
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`), {
      id: MARK,
      sessionId: SESSION,
      studentId: "stu_a",
      studentName: "Ana Cruz",
      subject: "Physics",
      section: "Grade 10 - Rizal",
      date: "2026-03-03",
      status: "present",
      isDeleted: false,
    });
  });
}

beforeEach(seed);

describe("the session", () => {
  it("is readable by the staff who run classes", async () => {
    for (const [role, uid] of [
      ["faculty", "teacher_a"],
      ["principal", "principal_a"],
      ["registrar", "registrar_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/classSessions/${SESSION}`)));
    }
  });

  it("is not readable by a student or a parent", async () => {
    // Their line in the register is a mark, and that is what they read.
    // The session is who taught it and how the whole section came out.
    for (const [role, uid] of [
      ["student", "student_a"],
      ["parent", "parent_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, `schools/${SCHOOL}/classSessions/${SESSION}`)));
    }
  });

  it("cannot be written by anyone, including the teacher who took it", async () => {
    // The callables are the only door. A teacher who could write here
    // could open a session for a class that is not on the timetable, or
    // reopen one from last term.
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/classSessions/${SESSION}`), {status: "closed"})
    );
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/classSessions/forged`), {subject: "Physics"})
    );
    await assertFails(deleteDoc(doc(db, `schools/${SCHOOL}/classSessions/${SESSION}`)));
  });
});

describe("a mark", () => {
  it("is readable by the student it is about", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
  });

  it("is readable by that student's parent", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
  });

  it("is not readable by another child's parent", async () => {
    const db = contextAs("parent", "parent_b").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
  });

  it("is not readable by another student", async () => {
    const db = contextAs("student", "student_z").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
  });

  it("is readable by the staff who need it", async () => {
    for (const [role, uid] of [
      ["faculty", "teacher_a"],
      ["guidance", "guidance_a"],
      ["registrar", "registrar_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
    }
  });

  it("cannot be marked by the student themselves", async () => {
    // The one-way boundary the QR scanner already draws: a compromised
    // student device must not be able to mark itself present.
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`), {status: "present"})
    );
  });

  it("cannot be written by the teacher either -- only the callable", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`), {status: "absent"})
    );
    await assertFails(deleteDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/${MARK}`)));
  });

  it("is closed off with the rest of a suspended school", async () => {
    const db = contextAs("faculty", "teacher_a", LAPSED).firestore();
    await assertFails(getDoc(doc(db, `schools/${LAPSED}/subjectAttendance/${MARK}`)));
  });
});

/**
 * The counter behind the class code.
 *
 * Eight wrong codes and the door stops answering for ten minutes. That
 * only means anything while the count is out of reach: a client that
 * could read it would learn how many guesses it has left, and one that
 * could write it could give itself more. So it is nobody's but the
 * server's, and this is what says so.
 */
describe("the wrong-code counter", () => {
  const ATTEMPT = `schools/${SCHOOL}/meetingAttempts/${SESSION}_student_a`;

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), ATTEMPT), {
        schoolId: SCHOOL,
        sessionId: SESSION,
        uid: "student_a",
        wrong: 3,
      });
    });
  });

  it("is not readable by the person it counts", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertFails(getDoc(doc(db, ATTEMPT)));
  });

  it("is not writable by them either", async () => {
    // The direction that would be a hole: eight guesses back to zero.
    const db = contextAs("student", "student_a").firestore();
    await assertFails(setDoc(doc(db, ATTEMPT), {wrong: 0}));
    await assertFails(updateDoc(doc(db, ATTEMPT), {wrong: 0}));
    await assertFails(deleteDoc(doc(db, ATTEMPT)));
  });

  it("is not reachable by the staff of the school either", async () => {
    // Not a secret being kept from teachers so much as a document with
    // no reason to be read by anybody: the server writes it, the server
    // reads it, and nothing else has business with it.
    for (const role of ["faculty", "admin", "director", "registrar"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertFails(getDoc(doc(db, ATTEMPT)));
      await assertFails(setDoc(doc(db, ATTEMPT), {wrong: 0}));
    }
  });
});
