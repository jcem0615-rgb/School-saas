import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_student_test";

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

async function seedFixtures() {
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
    await setDoc(doc(db, `schools/${SCHOOL}/students/student_1`), {
      id: "student_1",
      schoolId: SCHOOL,
      userId: "student_1_uid",
      section: "7-A",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/grades/grade_1`), {
      studentId: "student_1",
      subject: "Math",
      score: 90,
      maxScore: 100,
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

describe("student self-access to grades", () => {
  test("the linked student can read their own grade", async () => {
    await seedFixtures();
    const student = contextAs("student", "student_1_uid");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/grades/grade_1`)));
  });

  test("a different student cannot read this grade", async () => {
    await seedFixtures();
    const otherStudent = contextAs("student", "student_2_uid");
    await assertFails(getDoc(doc(otherStudent.firestore(), `schools/${SCHOOL}/grades/grade_1`)));
  });
});

describe("promissory note filing (reuses the generic approvals mechanism)", () => {
  test("a student can file a promissory note request for themselves", async () => {
    await seedFixtures();
    const student = contextAs("student", "student_1_uid");
    await assertSucceeds(
      setDoc(doc(student.firestore(), `schools/${SCHOOL}/approvals/pn_1`), {
        type: "promissory_note",
        title: "Payment deferral request",
        requestedByRole: "student",
        status: "pending",
        details: {amount: 1500},
        createdBy: "student_1_uid",
      })
    );
  });

  test("a student cannot decide (approve) their own promissory note", async () => {
    await seedFixtures();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/pn_2`), {
        type: "promissory_note",
        status: "pending",
        requestedByRole: "student",
      });
    });
    const student = contextAs("student", "student_1_uid");
    await assertFails(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/approvals/pn_2`), {status: "approved"})
    );
  });
});
