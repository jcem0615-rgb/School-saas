import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_principal_test";

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

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/hs_student`), {
      id: "hs_student",
      educationLevel: "high_school",
    });
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/students/elem_student`), {
      id: "elem_student",
      educationLevel: "elementary",
    });
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_hs`), {
      studentId: "hs_student",
      category: "behavioral",
      notes: "Confidential",
    });

    // A Principal scoped to High School only.
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/users/principal_hs`), {
      role: "principal",
      employeeInfo: {assignedDivision: "high_school"},
    });
    // A Principal with no scope configured -- should behave school-wide,
    // same as before this role existed for any other staff type.
    await setDoc(doc(context.firestore(), `schools/${SCHOOL}/users/principal_unrestricted`), {
      role: "principal",
      employeeInfo: {department: "Administration", position: "Principal"},
    });
  });
}

describe("division-scoped Principal", () => {
  test("CAN read a student in their own division", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertSucceeds(getDoc(doc(principal.firestore(), `schools/${SCHOOL}/students/hs_student`)));
  });

  test("CANNOT read a student in a different division", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertFails(getDoc(doc(principal.firestore(), `schools/${SCHOOL}/students/elem_student`)));
  });

  test("CAN read a guidance record for their own division (welfare oversight)", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertSucceeds(getDoc(doc(principal.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_hs`)));
  });

  test("CANNOT author a guidance record -- read-only oversight, not a Guidance Office action", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertFails(
      setDoc(doc(principal.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_forged`), {
        studentId: "hs_student",
        category: "academic",
        notes: "Should not be allowed",
      })
    );
  });

  test("CANNOT edit a student record -- Principal is read-only there, unlike Registrar", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertFails(
      updateDoc(doc(principal.firestore(), `schools/${SCHOOL}/students/hs_student`), {
        gradeLevel: "Grade 12",
      })
    );
  });
});

describe("unrestricted Principal (no assignedDivision configured)", () => {
  test("CAN read students in any division", async () => {
    await seed();
    const principal = contextAs("principal", "principal_unrestricted");
    await assertSucceeds(getDoc(doc(principal.firestore(), `schools/${SCHOOL}/students/hs_student`)));
    await assertSucceeds(getDoc(doc(principal.firestore(), `schools/${SCHOOL}/students/elem_student`)));
  });
});

describe("Principal leadership actions", () => {
  test("CAN create an announcement", async () => {
    await seed();
    const principal = contextAs("principal", "principal_hs");
    await assertSucceeds(
      setDoc(doc(principal.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "High School Assembly",
        body: "All HS students report to the gym.",
        createdBy: "principal_hs",
      })
    );
  });

  test("CAN decide (approve) a pending approval request", async () => {
    await seed();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_1`), {
        status: "pending",
        requestedByRole: "faculty",
      });
    });
    const principal = contextAs("principal", "principal_hs");
    await assertSucceeds(
      updateDoc(doc(principal.firestore(), `schools/${SCHOOL}/approvals/req_1`), {status: "approved"})
    );
  });

  test("cannot re-decide a request that's already been decided (pending-only guard still applies)", async () => {
    await seed();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_2`), {
        status: "approved",
        requestedByRole: "faculty",
      });
    });
    const principal = contextAs("principal", "principal_hs");
    await assertFails(
      updateDoc(doc(principal.firestore(), `schools/${SCHOOL}/approvals/req_2`), {status: "rejected"})
    );
  });
});
