import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL_S = "school_suspended";

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

async function seedSuspendedSchool() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: calling context.firestore()
    // again after a write has started the instance throws
    // "Firestore has already been started and its settings can no longer
    // be changed", failing the test for a reason unrelated to rules.
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL_S}`), {
      schoolId: SCHOOL_S,
      currentStatus: "suspended",
    });
    await setDoc(doc(db, `schools/${SCHOOL_S}/users/user_1`), {
      id: "user_1",
      schoolId: SCHOOL_S,
      role: "faculty",
      firstName: "Test",
    });
    await setDoc(doc(db, `schools/${SCHOOL_S}/announcements/ann_1`), {
      title: "Some announcement",
    });
  });
}

describe("suspended school data access", () => {
  test("a user can still read their own profile while the school is suspended", async () => {
    await seedSuspendedSchool();
    const user = testEnv.authenticatedContext("user_1", {
      schoolId: SCHOOL_S,
      role: "faculty",
      status: "active",
      mustChangePassword: false,
    });

    await assertSucceeds(getDoc(doc(user.firestore(), `schools/${SCHOOL_S}/users/user_1`)));
  });

  test("a user CANNOT read other tenant collections while the school is suspended", async () => {
    await seedSuspendedSchool();
    const user = testEnv.authenticatedContext("user_1", {
      schoolId: SCHOOL_S,
      role: "faculty",
      status: "active",
      mustChangePassword: false,
    });

    await assertFails(getDoc(doc(user.firestore(), `schools/${SCHOOL_S}/announcements/ann_1`)));
  });

  test("the same collection IS readable once the school is active again", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: calling context.firestore()
    // again after a write has started the instance throws
    // "Firestore has already been started and its settings can no longer
    // be changed", failing the test for a reason unrelated to rules.
    const db = context.firestore();
      await setDoc(doc(db, `platform_subscriptions/${SCHOOL_S}`), {
        schoolId: SCHOOL_S,
        currentStatus: "active",
      });
      await setDoc(doc(db, `schools/${SCHOOL_S}/announcements/ann_1`), {
        title: "Some announcement",
      });
    });

    const user = testEnv.authenticatedContext("user_1", {
      schoolId: SCHOOL_S,
      role: "faculty",
      status: "active",
      mustChangePassword: false,
    });

    await assertSucceeds(getDoc(doc(user.firestore(), `schools/${SCHOOL_S}/announcements/ann_1`)));
  });
});
