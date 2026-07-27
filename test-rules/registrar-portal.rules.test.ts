import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_registrar_test";

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
    await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/student_1`), {
      id: "student_1",
      schoolId: SCHOOL,
      studentNumber: "S-2026-000001",
      firstName: "Juan",
      lastName: "Dela Cruz",
      gradeLevel: "Grade 7",
      section: "A",
      status: "enrolled",
      balance: 1000,
      userId: null,
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

describe("students: creation is server-only", () => {
  test("registrar cannot create a student doc directly from the client", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_forged`), {
        studentNumber: "S-2026-999999",
        firstName: "Forged",
        lastName: "Record",
        balance: 0,
      })
    );
  });
});

describe("students: update field boundary", () => {
  test("registrar CAN update gradeLevel and section", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_1`), {
        gradeLevel: "Grade 8",
        section: "B",
      })
    );
  });

  test("registrar CANNOT update balance directly -- must go through Payments callables", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_1`), {
        balance: 0,
      })
    );
  });

  test("registrar CANNOT set userId directly -- must go through provisionUser's linking step", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_1`), {
        userId: "some_uid_the_registrar_chose",
      })
    );
  });

  test("registrar CANNOT change studentNumber", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/student_1`), {
        studentNumber: "S-2026-000002",
      })
    );
  });

  test("faculty cannot update a student record at all (read-only role here)", async () => {
    await seedFixtures();
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/students/student_1`), {
        gradeLevel: "Grade 8",
      })
    );
  });
});
