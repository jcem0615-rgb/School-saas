import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc, serverTimestamp} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_submissions_test";

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

function contextAs(role: string, uid: string) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/student_a`), {
      role: "student",
      status: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_a`), {
      role: "parent",
      status: "active",
      linkedStudentIds: ["stu_a"],
    });
    // Student A's own submission, written server-side so the tests below
    // start from a document that already exists.
    await setDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`), {
      courseworkId: "cw_1",
      studentId: "stu_a",
      userId: "student_a",
      answer: "my answer",
      submittedAt: new Date("2026-06-01T09:00:00Z"),
      isDeleted: false,
    });
  });
}

/**
 * courseworkSubmissions is the only collection in this schema a student
 * account writes to -- everything else they touch is read-only. These
 * pin the two things that gives them a motive to get wrong: whose work
 * it is, and when it arrived.
 */
describe("handing work in", () => {
  test("a student CAN submit as themselves, with the server's clock", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_2_stu_a`), {
        courseworkId: "cw_2",
        studentId: "stu_a",
        userId: "student_a",
        answer: "here is my work",
        submittedAt: serverTimestamp(),
        isDeleted: false,
      })
    );
  });

  test("a student CANNOT submit with their own timestamp", async () => {
    // The whole late/on-time distinction rests on this. A client-supplied
    // submittedAt would let a student hand in a week late and label it
    // as Monday morning.
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_2_stu_a`), {
        courseworkId: "cw_2",
        studentId: "stu_a",
        userId: "student_a",
        answer: "here is my work",
        submittedAt: new Date("2026-01-01T00:00:00Z"),
        isDeleted: false,
      })
    );
  });

  test("a student CANNOT submit as somebody else", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_2_stu_b`), {
        courseworkId: "cw_2",
        studentId: "stu_b",
        userId: "student_b",
        answer: "not mine to hand in",
        submittedAt: serverTimestamp(),
        isDeleted: false,
      })
    );
  });

  test("a faculty member CANNOT write a submission on a student's behalf", async () => {
    // Not a hostile case -- a teacher typing in work for an absent
    // student sounds helpful. But it makes the record a claim about who
    // did the work that nobody can check afterwards.
    await seed();
    const db = contextAs("faculty", "faculty_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_2_stu_a`), {
        courseworkId: "cw_2",
        studentId: "stu_a",
        userId: "student_a",
        answer: "dictated to me",
        submittedAt: serverTimestamp(),
        isDeleted: false,
      })
    );
  });
});

describe("revising work", () => {
  test("a student CAN replace their own answer", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`), {
        answer: "corrected answer",
        updatedAt: serverTimestamp(),
      })
    );
  });

  test("a student CANNOT rewrite when it was handed in", async () => {
    // The one edit that would turn a late submission into an on-time one.
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`), {
        answer: "corrected answer",
        submittedAt: new Date("2026-05-01T09:00:00Z"),
        updatedAt: serverTimestamp(),
      })
    );
  });

  test("a student CANNOT edit somebody else's submission", async () => {
    await seed();
    const db = contextAs("student", "student_b").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`), {
        answer: "tampered",
        updatedAt: serverTimestamp(),
      })
    );
  });

  test("nobody can delete handed-in work", async () => {
    await seed();
    const student = contextAs("student", "student_a").firestore();
    await assertFails(deleteDoc(doc(student, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`)));
  });
});

describe("who can read a submission", () => {
  test("the student who wrote it CAN", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`)));
  });

  test("a teacher CAN, because marking needs the whole class", async () => {
    await seed();
    const db = contextAs("faculty", "faculty_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`)));
  });

  test("the linked parent CAN", async () => {
    await seed();
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`)));
  });

  test("another student CANNOT read a classmate's answers", async () => {
    // Otherwise the collection is a shared answer key.
    await seed();
    const db = contextAs("student", "student_b").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/courseworkSubmissions/cw_1_stu_a`)));
  });
});
