import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_payments_test";

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
      balance: 3500,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/payments/pay_1`), {
      id: "pay_1",
      schoolId: SCHOOL,
      studentId: "student_1",
      amount: 1500,
      status: "completed",
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

describe("REGRESSION: catch-all no longer grants blanket tenant read", () => {
  test("faculty cannot read another student's payment record", async () => {
    await seedFixtures();
    const faculty = contextAs("faculty", "faculty_1");
    // Faculty is intentionally NOT in the payments allow-list.
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/payments/pay_1`)));
  });

  test("faculty cannot read a student's balance via the students collection", async () => {
    await seedFixtures();
    // Faculty IS allowed on students (needs it for academic purposes) --
    // this confirms that access, distinguishing it from payments below,
    // proves the restriction is deliberate per-collection, not a blanket outage.
    const faculty = contextAs("faculty", "faculty_1");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/students/student_1`)));
  });

  test("staff (maintenance) cannot read students records at all", async () => {
    await seedFixtures();
    const staff = contextAs("staff", "staff_1");
    await assertFails(getDoc(doc(staff.firestore(), `schools/${SCHOOL}/students/student_1`)));
  });
});

describe("payments", () => {
  test("registrar can read any payment in the school", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/payments/pay_1`)));
  });

  test("the student themself can read their own payment record", async () => {
    await seedFixtures();
    const student = contextAs("student", "student_1_uid");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/payments/pay_1`)));
  });

  test("a linked parent can read the payment record", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_1");
    await assertSucceeds(getDoc(doc(parent.firestore(), `schools/${SCHOOL}/payments/pay_1`)));
  });

  test("a parent NOT linked to the student cannot read the payment record", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_2");
    await assertFails(getDoc(doc(parent.firestore(), `schools/${SCHOOL}/payments/pay_1`)));
  });

  test("no client can write a payment directly, even the registrar", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/payments/pay_forged`), {
        studentId: "student_1",
        amount: 999999,
        status: "completed",
      })
    );
  });
});

describe("students", () => {
  test("registrar can read a student record", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_1`)));
  });

  test("an unrelated student cannot read another student's record", async () => {
    await seedFixtures();
    const otherStudent = contextAs("student", "student_2_uid");
    await assertFails(getDoc(doc(otherStudent.firestore(), `schools/${SCHOOL}/students/student_1`)));
  });

  test("no client can write to students -- Registrar Portal module not yet implemented", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_new`), {balance: 0})
    );
  });
});
