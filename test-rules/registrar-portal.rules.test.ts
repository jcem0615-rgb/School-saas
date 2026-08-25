import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

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

describe("documentReleases: an append-only record of what left the office", () => {
  const RELEASE = `schools/${SCHOOL}/documentReleases/rel_1`;

  function release(overrides: Record<string, unknown> = {}) {
    return {
      id: "rel_1",
      schoolId: SCHOOL,
      studentId: "student_1",
      studentName: "Juan Dela Cruz",
      document: "form_137",
      copies: 1,
      purpose: "Transfer to Santa Rosa NHS",
      releasedToName: "Ana Dela Cruz",
      releasedToRelation: "Mother",
      releasedByName: "Registrar One",
      releasedBy: "registrar_1",
      isDeleted: false,
      ...overrides,
    };
  }

  async function seedRelease() {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), RELEASE), release());
    });
  }

  test("registrar CAN log a release", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(setDoc(doc(registrar.firestore(), RELEASE), release()));
  });

  test("registrar CANNOT log a release in somebody else's name", async () => {
    // An entry naming the wrong person as the releaser is worse than no
    // entry: it is a false answer to the only question the log exists
    // to answer.
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(doc(registrar.firestore(), RELEASE), release({releasedBy: "registrar_2"}))
    );
  });

  test("faculty cannot log a release", async () => {
    await seedFixtures();
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      setDoc(doc(faculty.firestore(), RELEASE), release({releasedBy: "faculty_1"}))
    );
  });

  test("nobody can edit a logged release -- not even the director", async () => {
    await seedFixtures();
    await seedRelease();
    for (const [role, uid] of [["registrar", "registrar_1"], ["director", "director_1"], ["admin", "admin_1"]]) {
      const ctx = contextAs(role, uid);
      await assertFails(
        updateDoc(doc(ctx.firestore(), RELEASE), {purpose: "Something else"})
      );
    }
  });

  test("nobody can delete a logged release -- not even the director", async () => {
    await seedFixtures();
    await seedRelease();
    for (const [role, uid] of [["registrar", "registrar_1"], ["director", "director_1"], ["admin", "admin_1"]]) {
      const ctx = contextAs(role, uid);
      await assertFails(deleteDoc(doc(ctx.firestore(), RELEASE)));
    }
  });

  test("the registrar can read what was released", async () => {
    await seedFixtures();
    await seedRelease();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(getDoc(doc(registrar.firestore(), RELEASE)));
  });

  test("a student can read the releases on their own record", async () => {
    // It is a record of what the school did with their documents. A
    // family that cannot see it has to phone up to ask.
    await seedFixtures();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `schools/${SCHOOL}/students/student_1`), {
        id: "student_1",
        schoolId: SCHOOL,
        studentNumber: "S-2026-000001",
        firstName: "Juan",
        lastName: "Dela Cruz",
        gradeLevel: "Grade 7",
        section: "A",
        status: "enrolled",
        balance: 1000,
        userId: "student_uid_1",
      });
      await setDoc(doc(db, RELEASE), release());
    });
    const student = contextAs("student", "student_uid_1");
    await assertSucceeds(getDoc(doc(student.firestore(), RELEASE)));
  });
});
