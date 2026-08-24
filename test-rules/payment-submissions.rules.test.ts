import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * Online payment is submit -> review -> apply, and these tests pin the two
 * properties that make the review step worth anything:
 *
 *  1. A family can file a claim but can never mark it approved, and can
 *     never edit it after filing. Approval happens only through
 *     decidePaymentSubmission (Admin SDK), which bypasses these rules.
 *  2. Only the roles that handle money can change WHERE money is sent.
 *     Repointing the school's QR at another account would be the single
 *     most damaging write in this system.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_paysub_test";

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

function contextAs(role: string, uid = `${role}_1`) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: a second call after a write
    // throws "Firestore has already been started".
    const db = context.firestore();

    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    // student_1's own record, and one belonging to someone else.
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_own`), {
      schoolId: SCHOOL,
      userId: "student_1",
      educationLevel: "high_school",
      department: null,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_other`), {
      schoolId: SCHOOL,
      userId: "student_other",
      educationLevel: "high_school",
      department: null,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["stu_own"],
    });
  });
}

const submission = (uid: string, studentId: string, extra: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  studentId,
  studentName: "Test Student",
  amount: 2500,
  method: "gcash",
  purpose: "tuition",
  referenceNumber: "GC-1234567",
  status: "pending",
  createdBy: uid,
  isDeleted: false,
  ...extra,
});

beforeEach(seedFixtures);

describe("filing a submission", () => {
  test("a student can file one against their own record", async () => {
    const student = contextAs("student");
    await assertSucceeds(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s1`),
        submission("student_1", "stu_own")
      )
    );
  });

  test("a student cannot file one against someone else's record", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s2`),
        submission("student_1", "stu_other")
      )
    );
  });

  test("a parent can file one for a linked child", async () => {
    const parent = contextAs("parent");
    await assertSucceeds(
      setDoc(
        doc(parent.firestore(), `schools/${SCHOOL}/paymentSubmissions/s3`),
        submission("parent_1", "stu_own")
      )
    );
  });

  test("a parent cannot file one for a child who is not theirs", async () => {
    const parent = contextAs("parent");
    await assertFails(
      setDoc(
        doc(parent.firestore(), `schools/${SCHOOL}/paymentSubmissions/s4`),
        submission("parent_1", "stu_other")
      )
    );
  });

  // The heart of it: approval is a decision, never an input.
  test("a submission cannot be filed already approved", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s5`),
        submission("student_1", "stu_own", {status: "approved"})
      )
    );
  });

  test("a submission cannot be filed under someone else's name", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s6`),
        submission("registrar_1", "stu_own")
      )
    );
  });

  test("a reference number is required", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s7`),
        submission("student_1", "stu_own", {referenceNumber: ""})
      )
    );
  });

  test("a non-positive amount is refused", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/paymentSubmissions/s8`),
        submission("student_1", "stu_own", {amount: 0})
      )
    );
  });
});

describe("a filed submission is immutable from the client", () => {
  const path = `schools/${SCHOOL}/paymentSubmissions/s_locked`;

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), path), submission("student_1", "stu_own"));
    });
  });

  test("the submitter cannot approve their own claim", async () => {
    const student = contextAs("student");
    await assertFails(
      updateDoc(doc(student.firestore(), path), {status: "approved"})
    );
  });

  test("the submitter cannot change the amount after filing", async () => {
    const student = contextAs("student");
    await assertFails(updateDoc(doc(student.firestore(), path), {amount: 99999}));
  });

  // Even a registrar goes through the callable, so the payment and the
  // status change land in one transaction.
  test("not even a registrar can approve by direct write", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), path), {status: "approved"})
    );
  });

  test("no one can delete a submission", async () => {
    const registrar = contextAs("registrar");
    await assertFails(deleteDoc(doc(registrar.firestore(), path)));
  });
});

describe("reading submissions", () => {
  const path = `schools/${SCHOOL}/paymentSubmissions/s_read`;

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), path), submission("student_1", "stu_own"));
    });
  });

  test("the registrar can read it, to review it", async () => {
    const registrar = contextAs("registrar");
    await assertSucceeds(getDoc(doc(registrar.firestore(), path)));
  });

  test("the submitter can follow their own claim", async () => {
    const student = contextAs("student");
    await assertSucceeds(getDoc(doc(student.firestore(), path)));
  });

  test("an unrelated student cannot read someone else's claim", async () => {
    const other = contextAs("student", "student_other");
    await assertFails(getDoc(doc(other.firestore(), path)));
  });

  test("faculty have no business seeing payment claims", async () => {
    const faculty = contextAs("faculty");
    await assertFails(getDoc(doc(faculty.firestore(), path)));
  });
});

describe("payment settings -- where the money goes", () => {
  const path = `schools/${SCHOOL}/settings/payments`;

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), path), {
        schoolId: SCHOOL,
        qrCodeUrl: "https://example.test/qr.png",
        accountNumber: "0917 555 0100",
      });
    });
  });

  test("a student can read it -- they cannot pay otherwise", async () => {
    const student = contextAs("student");
    await assertSucceeds(getDoc(doc(student.firestore(), path)));
  });

  test("a registrar can publish it", async () => {
    const registrar = contextAs("registrar");
    await assertSucceeds(
      setDoc(doc(registrar.firestore(), path), {
        schoolId: SCHOOL,
        qrCodeUrl: "https://example.test/new-qr.png",
      })
    );
  });

  // Repointing the QR is how you would divert every family's tuition.
  test("a student cannot repoint the QR at their own account", async () => {
    const student = contextAs("student");
    await assertFails(
      updateDoc(doc(student.firestore(), path), {qrCodeUrl: "https://evil.test/qr.png"})
    );
  });

  test("faculty cannot change payment details either", async () => {
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), {accountNumber: "0917 000 0000"})
    );
  });
});
