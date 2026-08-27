import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_director_test";

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
    await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
  });
}

function contextAs(role: string, uid = `${role}_1`) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

describe("announcements", () => {
  // Faculty gained this when teachers were given a way to address their
  // own classes. The audience field is targeting, not access control, so
  // what the rule actually has to hold is authorship -- which is what
  // these two check.
  test("faculty can post as themselves", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty");
    await assertSucceeds(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
        createdBy: "faculty_1",
      })
    );
  });

  test("faculty cannot post under someone else's name", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty");
    await assertFails(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_2`), {
        title: "Test",
        body: "Body",
        createdBy: "director_1",
      })
    );
  });

  test("director can create an announcement", async () => {
    await seedActiveSubscription();
    const director = contextAs("director");
    await assertSucceeds(
      setDoc(doc(director.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
        createdBy: "director_1",
      })
    );
  });

  test("any tenant member can read announcements", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
      });
    });
    const student = contextAs("student");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/announcements/ann_1`)));
  });
});

describe("approvals", () => {
  test("staff can file a request for themselves", async () => {
    await seedActiveSubscription();
    const staff = contextAs("staff");
    await assertSucceeds(
      setDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_1`), {
        type: "material_request",
        title: "Need more chalk",
        requestedByRole: "staff",
        status: "pending",
        createdBy: "staff_1",
      })
    );
  });

  test("staff cannot file a request impersonating another role", async () => {
    await seedActiveSubscription();
    const staff = contextAs("staff");
    await assertFails(
      setDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_2`), {
        type: "material_request",
        title: "Suspicious",
        requestedByRole: "director", // lying about role
        status: "pending",
        createdBy: "staff_1",
      })
    );
  });

  test("staff cannot decide their own request", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_3`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_3`), {status: "approved"})
    );
  });

  test("director CAN decide a pending request", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_4`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const director = contextAs("director");
    await assertSucceeds(
      updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/req_4`), {status: "approved"})
    );
  });
});

describe("expenses", () => {
  test("faculty cannot read expenses", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/expenses/exp_1`), {amount: 500});
    });
    const faculty = contextAs("faculty");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/expenses/exp_1`)));
  });

  test("registrar CAN read expenses", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/expenses/exp_1`), {amount: 500});
    });
    const registrar = contextAs("registrar");
    await assertSucceeds(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/expenses/exp_1`)));
  });

  test("registrar cannot CREATE an expense (read-only role for this collection)", async () => {
    await seedActiveSubscription();
    const registrar = contextAs("registrar");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/expenses/exp_2`), {
        amount: 500,
        createdBy: "registrar_1",
      })
    );
  });
});
