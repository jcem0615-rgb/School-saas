import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_staff_guidance_test";

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

async function seedCommon() {
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
      userId: "student_1_uid",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      id: "parent_1",
      role: "parent",
      linkedStudentIds: ["student_1"],
    });
  });
}

describe("guidanceRecords: the strictest privacy boundary in the schema", () => {
  test("guidance counselor can read a guidance record", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_1`), {
        studentId: "student_1",
        category: "behavioral",
        notes: "Confidential note",
      });
    });
    const guidance = contextAs("guidance", "guidance_1");
    await assertSucceeds(getDoc(doc(guidance.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_1`)));
  });

  test("the student themself CANNOT read their own guidance record", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_2`), {
        studentId: "student_1",
        category: "behavioral",
        notes: "Confidential note",
      });
    });
    const student = contextAs("student", "student_1_uid");
    await assertFails(getDoc(doc(student.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_2`)));
  });

  test("the linked parent CANNOT read the guidance record", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_3`), {
        studentId: "student_1",
        category: "behavioral",
        notes: "Confidential note",
      });
    });
    const parent = contextAs("parent", "parent_1");
    await assertFails(getDoc(doc(parent.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_3`)));
  });

  test("faculty CANNOT read a guidance record (unlike coursework, attendance, etc.)", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_4`), {
        studentId: "student_1",
        category: "academic",
        notes: "Confidential note",
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_4`)));
  });

  test("registrar CANNOT read a guidance record", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_5`), {
        studentId: "student_1",
        category: "academic",
        notes: "Confidential note",
      });
    });
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/guidanceRecords/rec_5`)));
  });
});

describe("summons: visible to student/parent, unlike guidanceRecords", () => {
  test("the student themself CAN read a summons concerning them", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/summons/sm_1`), {
        studentId: "student_1",
        reason: "Please report to the guidance office",
        status: "pending",
      });
    });
    const student = contextAs("student", "student_1_uid");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/summons/sm_1`)));
  });

  test("the linked parent CAN read the summons", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/summons/sm_2`), {
        studentId: "student_1",
        reason: "Please report to the guidance office",
        status: "pending",
      });
    });
    const parent = contextAs("parent", "parent_1");
    await assertSucceeds(getDoc(doc(parent.firestore(), `schools/${SCHOOL}/summons/sm_2`)));
  });
});

describe("checklistItems and dailyReports: staff self-scoping", () => {
  test("a staff member cannot read a colleague's checklist item", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/checklistItems/item_1`), {
        staffId: "staff_1",
        task: "Clean classrooms",
      });
    });
    const otherStaff = contextAs("staff", "staff_2");
    await assertFails(getDoc(doc(otherStaff.firestore(), `schools/${SCHOOL}/checklistItems/item_1`)));
  });

  test("director can read any staff member's daily report (oversight)", async () => {
    await seedCommon();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/dailyReports/rep_1`), {
        staffId: "staff_1",
        content: "Fixed the AC unit",
      });
    });
    const director = contextAs("director", "director_1");
    await assertSucceeds(getDoc(doc(director.firestore(), `schools/${SCHOOL}/dailyReports/rep_1`)));
  });
});
