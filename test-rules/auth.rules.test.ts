/**
 * Run with the Firestore emulator:
 *   firebase emulators:exec --only firestore "jest test-rules/auth.rules.test.ts"
 *
 * Uses @firebase/rules-unit-testing to assert the security rules directly,
 * independent of any app or Cloud Function code -- this is what actually
 * proves tenant isolation holds, rather than just trusting the rules file
 * reads correctly.
 */
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;

const SCHOOL_A = "school_a";
const SCHOOL_B = "school_b";

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "school-saas-test",
    firestore: {
      rules: fs.readFileSync("firestore.rules", "utf8"),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

describe("tenant isolation on schools/{schoolId}/users", () => {
  test("a user cannot read another school's users collection", async () => {
    // Seed data as a trusted admin context (bypasses rules).
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL_B}/users/user_b1`), {
        id: "user_b1",
        schoolId: SCHOOL_B,
        role: "student",
        firstName: "Other",
        lastName: "School",
      });
    });

    const userFromSchoolA = testEnv.authenticatedContext("user_a1", {
      schoolId: SCHOOL_A,
      role: "registrar",
      status: "active",
      mustChangePassword: false,
    });

    await assertFails(
      getDoc(doc(userFromSchoolA.firestore(), `schools/${SCHOOL_B}/users/user_b1`))
    );
  });

  test("a user CAN read users within their own school", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL_A}/users/user_a2`), {
        id: "user_a2",
        schoolId: SCHOOL_A,
        role: "faculty",
        firstName: "Same",
        lastName: "School",
      });
    });

    const userFromSchoolA = testEnv.authenticatedContext("user_a1", {
      schoolId: SCHOOL_A,
      role: "registrar",
      status: "active",
      mustChangePassword: false,
    });

    await assertSucceeds(
      getDoc(doc(userFromSchoolA.firestore(), `schools/${SCHOOL_A}/users/user_a2`))
    );
  });

  test("a user can update their own phone number but NOT their own role", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL_A}/users/user_a1`), {
        id: "user_a1",
        schoolId: SCHOOL_A,
        role: "faculty",
        phone: "0900000000",
      });
    });

    const self = testEnv.authenticatedContext("user_a1", {
      schoolId: SCHOOL_A,
      role: "faculty",
      status: "active",
      mustChangePassword: false,
    });

    await assertSucceeds(
      updateDoc(doc(self.firestore(), `schools/${SCHOOL_A}/users/user_a1`), {
        phone: "0911111111",
      })
    );

    await assertFails(
      updateDoc(doc(self.firestore(), `schools/${SCHOOL_A}/users/user_a1`), {
        role: "director",
      })
    );
  });

  test("the audit log cannot be written from the client, even by an admin", async () => {
    const admin = testEnv.authenticatedContext("admin_a1", {
      schoolId: SCHOOL_A,
      role: "admin",
      status: "active",
      mustChangePassword: false,
    });

    await assertFails(
      setDoc(doc(admin.firestore(), `schools/${SCHOOL_A}/auditLog/fake_entry`), {
        action: "forged",
      })
    );
  });

  test("platform_schools is completely inaccessible to a non-owner", async () => {
    const director = testEnv.authenticatedContext("director_a1", {
      schoolId: SCHOOL_A,
      role: "director",
      status: "active",
      mustChangePassword: false,
    });

    await assertFails(getDoc(doc(director.firestore(), `platform_schools/${SCHOOL_A}`)));
  });
});
