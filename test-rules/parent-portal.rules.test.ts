import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
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

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: a second context.firestore()
    // after a write throws "Firestore has already been started".
    const db = context.firestore();

    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      id: "parent_1",
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["child_a", "child_b"],
    });

    // userId must be present even when unset: the students read rule
    // dereferences resource.data.userId directly, unlike educationLevel
    // and department which it reads via .get(field, default).
    for (const id of ["child_a", "child_b", "unrelated_child"]) {
      await setDoc(doc(db, `schools/${SCHOOL}/students/${id}`), {
        id,
        userId: null,
        firstName: "Child",
        lastName: id,
      });
    }
  });
}

describe("parent resolving linked children via whereIn(documentId())", () => {
  test("a parent can query exactly their linked children", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_1");
    const studentsRef = collection(parent.firestore(), `schools/${SCHOOL}/students`);

    const linkedOnly = query(studentsRef, where(documentId(), "in", ["child_a", "child_b"]));
    const snap = await assertSucceeds(getDocs(linkedOnly));
    expect(snap.docs.map((d) => d.id).sort()).toEqual(["child_a", "child_b"]);
  });

  test("widening the query to an unlinked child rejects the whole query", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_1");
    const studentsRef = collection(parent.firestore(), `schools/${SCHOOL}/students`);

    // Firestore rules are NOT filters. For a query, every document the
    // query could return must satisfy the read rule, or the entire query
    // is rejected -- unreadable documents are never silently dropped.
    // That is why ParentRepository.watchChildren() queries the linked IDs
    // it already holds instead of listing the collection, and it is what
    // stops a parent widening their own query to enumerate the student body.
    const tooWide = query(
      studentsRef,
      where(documentId(), "in", ["child_a", "child_b", "unrelated_child"])
    );
    await assertFails(getDocs(tooWide));
  });
});
