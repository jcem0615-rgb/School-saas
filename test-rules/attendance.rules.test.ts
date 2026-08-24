import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_attendance_test";

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

async function seedSchoolAndRecord() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: calling context.firestore()
    // again after a write has started the instance throws
    // "Firestore has already been started and its settings can no longer
    // be changed", failing the test for a reason unrelated to rules.
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/attendance/2026-07-21_student_1`), {
      id: "2026-07-21_student_1",
      schoolId: SCHOOL,
      personId: "student_1",
      personRole: "student",
      status: "present",
      date: "2026-07-21",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      id: "parent_1",
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["student_1"],
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_2`), {
      id: "parent_2",
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["some_other_student"],
    });
  });
}

function contextAs(role: string, uid: string) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

describe("attendance records", () => {
  test("the student themself can read their own attendance record", async () => {
    await seedSchoolAndRecord();
    const student = contextAs("student", "student_1");
    await assertSucceeds(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_1`))
    );
  });

  test("an unrelated student CANNOT read another student's attendance record", async () => {
    await seedSchoolAndRecord();
    const otherStudent = contextAs("student", "student_2");
    await assertFails(
      getDoc(doc(otherStudent.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_1`))
    );
  });

  test("faculty can read any student's attendance record (monitoring)", async () => {
    await seedSchoolAndRecord();
    const faculty = contextAs("faculty", "faculty_1");
    await assertSucceeds(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_1`))
    );
  });

  test("a parent linked to the student can read the record", async () => {
    await seedSchoolAndRecord();
    const parent = contextAs("parent", "parent_1");
    await assertSucceeds(
      getDoc(doc(parent.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_1`))
    );
  });

  test("a parent NOT linked to the student cannot read the record", async () => {
    await seedSchoolAndRecord();
    const parent = contextAs("parent", "parent_2");
    await assertFails(
      getDoc(doc(parent.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_1`))
    );
  });

  test("no client -- not even faculty -- can write an attendance record directly", async () => {
    await seedSchoolAndRecord();
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-07-21_student_9`), {
        personId: "student_9",
        status: "present",
      })
    );
  });
});
