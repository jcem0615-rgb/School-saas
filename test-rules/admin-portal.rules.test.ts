import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_admin_test";

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

async function seedActiveSubscription() {
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
    await setDoc(doc(db, `schools/${SCHOOL}/users/faculty_1`), {
      id: "faculty_1",
      schoolId: SCHOOL,
      role: "faculty",
      status: "active",
      employeeInfo: {department: "Math", position: "Teacher I"},
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

describe("teacherAssignments", () => {
  test("registrar cannot create a teacher assignment (read-only role here)", async () => {
    await seedActiveSubscription();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/teacherAssignments/a1`), {
        teacherId: "faculty_1",
        subject: "Math",
        section: "7-A",
        createdBy: "registrar_1",
      })
    );
  });

  test("admin can create a teacher assignment", async () => {
    await seedActiveSubscription();
    const admin = contextAs("admin", "admin_1");
    await assertSucceeds(
      setDoc(doc(admin.firestore(), `schools/${SCHOOL}/teacherAssignments/a2`), {
        teacherId: "faculty_1",
        subject: "Math",
        section: "7-A",
        createdBy: "admin_1",
      })
    );
  });

  test("faculty can read teacher assignments but staff (maintenance) cannot", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/teacherAssignments/a3`), {
        teacherId: "faculty_1",
        subject: "Math",
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    const staff = contextAs("staff", "staff_1");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/teacherAssignments/a3`)));
    await assertFails(getDoc(doc(staff.firestore(), `schools/${SCHOOL}/teacherAssignments/a3`)));
  });
});

describe("employeeInfo field boundary (User Approval / status protection)", () => {
  test("admin CAN update employeeInfo directly", async () => {
    await seedActiveSubscription();
    const admin = contextAs("admin", "admin_1");
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), `schools/${SCHOOL}/users/faculty_1`), {
        employeeInfo: {department: "Science", position: "Teacher II"},
      })
    );
  });

  test("admin CANNOT change status directly -- must go through setUserStatus callable", async () => {
    await seedActiveSubscription();
    const admin = contextAs("admin", "admin_1");
    await assertFails(
      updateDoc(doc(admin.firestore(), `schools/${SCHOOL}/users/faculty_1`), {
        status: "suspended",
      })
    );
  });
});
