import {
  initializeTestEnvironment,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, collection, query, where, documentId, getDocs} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_parent_test";

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

describe("parent resolving linked children via whereIn(documentId())", () => {
  test("a parent's whereIn query returns exactly their linked children, not other students", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
        schoolId: SCHOOL,
        currentStatus: "active",
      });
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/users/parent_1`), {
        id: "parent_1",
        schoolId: SCHOOL,
        role: "parent",
        linkedStudentIds: ["child_a", "child_b"],
      });
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/child_a`), {
        id: "child_a",
        firstName: "Child",
        lastName: "A",
      });
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/child_b`), {
        id: "child_b",
        firstName: "Child",
        lastName: "B",
      });
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/unrelated_child`), {
        id: "unrelated_child",
        firstName: "Unrelated",
        lastName: "Child",
      });
    });

    const parent = contextAs("parent", "parent_1");
    const studentsRef = collection(parent.firestore(), `schools/${SCHOOL}/students`);

    // Query for all three IDs (as the app's whereIn would if it didn't
    // already know which were linked) -- rules should silently exclude
    // the unrelated one rather than erroring the whole query.
    const q = query(studentsRef, where(documentId(), "in", ["child_a", "child_b", "unrelated_child"]));
    const snap = await assertSucceeds(getDocs(q));

    const returnedIds = snap.docs.map((d) => d.id).sort();
    expect(returnedIds).toEqual(["child_a", "child_b"]);
  });
});
