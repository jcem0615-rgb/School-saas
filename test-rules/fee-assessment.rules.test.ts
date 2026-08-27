import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * An assessment is the record behind a balance, and `balance` is
 * server-owned -- assessStudentFees and voidAssessment move both in one
 * transaction. These tests pin the two properties that make that worth
 * anything:
 *
 *  1. No client writes an assessment. Not the registrar who raised it,
 *     not the Director. A client that could write here directly could
 *     charge a family money with no balance behind it, or move a balance
 *     with no record of why.
 *  2. The family can read it. That is the entire reason the collection
 *     exists -- before it, a balance was a number with nothing behind it.
 *
 * Fee schedules are the other half: institutional configuration a family
 * is entitled to see, that only Director/Admin may publish.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_fees_test";

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
    const db = context.firestore();

    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_own`), {
      schoolId: SCHOOL,
      userId: "student_1",
      educationLevel: "high_school",
      department: null,
      balance: 17000,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_other`), {
      schoolId: SCHOOL,
      userId: "student_other",
      educationLevel: "high_school",
      department: null,
      balance: 12500,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["stu_own"],
    });

    // Written with rules disabled, exactly as the callable's Admin SDK
    // write would land.
    await setDoc(doc(db, `schools/${SCHOOL}/assessments/a_own`), {
      schoolId: SCHOOL,
      studentId: "stu_own",
      studentName: "Own Student",
      schoolYear: "2026-2027",
      items: [{label: "Tuition", amount: 15000, category: "tuition"}],
      total: 17000,
      assessedBy: "registrar_1",
      assessedByName: "Registrar",
      voidedAt: null,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/assessments/a_other`), {
      schoolId: SCHOOL,
      studentId: "stu_other",
      studentName: "Other Student",
      schoolYear: "2026-2027",
      items: [{label: "Tuition", amount: 12500, category: "tuition"}],
      total: 12500,
      assessedBy: "registrar_1",
      assessedByName: "Registrar",
      voidedAt: null,
      isDeleted: false,
    });
  });
}

const structure = (extra: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  name: "Grade 10 - Full Year",
  educationLevel: "high_school",
  gradeLevel: "Grade 10",
  schoolYear: "2026-2027",
  items: [{label: "Tuition", amount: 15000, category: "tuition"}],
  total: 15000,
  isActive: true,
  isDeleted: false,
  ...extra,
});

const assessment = (studentId: string) => ({
  schoolId: SCHOOL,
  studentId,
  studentName: "Test Student",
  schoolYear: "2026-2027",
  items: [{label: "Tuition", amount: 15000, category: "tuition"}],
  total: 15000,
  assessedBy: "registrar_1",
  assessedByName: "Registrar",
  voidedAt: null,
  isDeleted: false,
});

beforeEach(seedFixtures);

describe("publishing fee schedules", () => {
  test("an admin can publish one", async () => {
    const admin = contextAs("admin");
    await assertSucceeds(
      setDoc(doc(admin.firestore(), `schools/${SCHOOL}/feeStructures/f1`), structure())
    );
  });

  test("a director can publish one", async () => {
    const director = contextAs("director");
    await assertSucceeds(
      setDoc(doc(director.firestore(), `schools/${SCHOOL}/feeStructures/f2`), structure())
    );
  });

  // A registrar assesses fees; they do not decide what the fees are.
  test("a registrar cannot publish one", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/feeStructures/f3`), structure())
    );
  });

  test("a student cannot publish one", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(doc(student.firestore(), `schools/${SCHOOL}/feeStructures/f4`), structure())
    );
  });

  // Every assessment cites its schedule by name, so the schedule has to
  // outlive the school's use of it. Retiring is an update, not a delete.
  test("nobody can delete one, not even an admin", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `schools/${SCHOOL}/feeStructures/f5`),
        structure()
      );
    });
    const admin = contextAs("admin");
    await assertFails(
      deleteDoc(doc(admin.firestore(), `schools/${SCHOOL}/feeStructures/f5`))
    );
  });

  test("an admin can retire one by clearing isActive", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `schools/${SCHOOL}/feeStructures/f6`),
        structure()
      );
    });
    const admin = contextAs("admin");
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), `schools/${SCHOOL}/feeStructures/f6`), {
        isActive: false,
      })
    );
  });

  test("a student can read the schedule they are charged under", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `schools/${SCHOOL}/feeStructures/f7`),
        structure()
      );
    });
    const student = contextAs("student");
    await assertSucceeds(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/feeStructures/f7`))
    );
  });
});

describe("writing assessments", () => {
  // The heart of it: the balance and the record move together or not at
  // all, and only the callable can move both.
  test("a registrar cannot write one directly", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      setDoc(
        doc(registrar.firestore(), `schools/${SCHOOL}/assessments/new1`),
        assessment("stu_own")
      )
    );
  });

  test("a director cannot write one directly either", async () => {
    const director = contextAs("director");
    await assertFails(
      setDoc(
        doc(director.firestore(), `schools/${SCHOOL}/assessments/new2`),
        assessment("stu_own")
      )
    );
  });

  test("a student cannot charge themselves less", async () => {
    const student = contextAs("student");
    await assertFails(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/assessments/a_own`), {
        total: 0,
      })
    );
  });

  // Voiding is a reversal that moves the balance back; deleting would
  // leave a figure nobody could account for.
  test("nobody can delete one", async () => {
    const admin = contextAs("admin");
    await assertFails(
      deleteDoc(doc(admin.firestore(), `schools/${SCHOOL}/assessments/a_own`))
    );
  });

  test("a registrar cannot mark one voided by hand", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/assessments/a_own`), {
        voidedAt: new Date(),
        voidReason: "changed my mind",
      })
    );
  });
});

describe("reading assessments", () => {
  test("a student can read their own", async () => {
    const student = contextAs("student");
    await assertSucceeds(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/assessments/a_own`))
    );
  });

  test("a student cannot read another student's", async () => {
    const student = contextAs("student");
    await assertFails(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/assessments/a_other`))
    );
  });

  test("a parent can read a linked child's", async () => {
    const parent = contextAs("parent");
    await assertSucceeds(
      getDoc(doc(parent.firestore(), `schools/${SCHOOL}/assessments/a_own`))
    );
  });

  test("a parent cannot read an unlinked student's", async () => {
    const parent = contextAs("parent");
    await assertFails(
      getDoc(doc(parent.firestore(), `schools/${SCHOOL}/assessments/a_other`))
    );
  });

  test("a registrar can read any student's", async () => {
    const registrar = contextAs("registrar");
    await assertSucceeds(
      getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/assessments/a_other`))
    );
  });

  test("a faculty member cannot read them at all", async () => {
    const faculty = contextAs("faculty");
    await assertFails(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/assessments/a_own`))
    );
  });
});
