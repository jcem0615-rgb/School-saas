import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_faculty_test";

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

function contextAs(role: string, uid: string) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

describe("courseworkItems", () => {
  test("faculty cannot create coursework attributed to another teacher", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/courseworkItems/item_1`), {
        type: "lesson",
        title: "Test",
        teacherId: "faculty_2",
        published: true,
      })
    );
  });

  test("faculty CAN create coursework attributed to themselves", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty", "faculty_1");
    await assertSucceeds(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/courseworkItems/item_2`), {
        type: "lesson",
        title: "Test",
        teacherId: "faculty_1",
        published: true,
      })
    );
  });

  test("a student CANNOT read an unpublished draft", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/courseworkItems/draft_1`), {
        type: "assignment",
        title: "Draft",
        teacherId: "faculty_1",
        published: false,
      });
    });
    const student = contextAs("student", "student_1");
    await assertFails(getDoc(doc(student.firestore(), `schools/${SCHOOL}/courseworkItems/draft_1`)));
  });

  test("a student CAN read a published item", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/courseworkItems/pub_1`), {
        type: "assignment",
        title: "Published",
        teacherId: "faculty_1",
        published: true,
      });
    });
    const student = contextAs("student", "student_1");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/courseworkItems/pub_1`)));
  });

  test("another faculty member CAN read a colleague's unpublished draft (staff visibility)", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/courseworkItems/draft_2`), {
        type: "quiz",
        title: "Draft Quiz",
        teacherId: "faculty_1",
        published: false,
      });
    });
    const otherFaculty = contextAs("faculty", "faculty_2");
    await assertSucceeds(getDoc(doc(otherFaculty.firestore(), `schools/${SCHOOL}/courseworkItems/draft_2`)));
  });
});

describe("grades", () => {
  test("faculty cannot reassign a grade to a different student on update", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/grades/grade_1`), {
        studentId: "student_1",
        score: 90,
        maxScore: 100,
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/grades/grade_1`), {
        studentId: "student_2",
      })
    );
  });

  test("faculty CAN correct a score on an existing grade", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/grades/grade_2`), {
        studentId: "student_1",
        score: 85,
        maxScore: 100,
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    await assertSucceeds(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/grades/grade_2`), {
        score: 88,
      })
    );
  });
});

describe("personal activity history (auditLog self-read)", () => {
  test("a faculty member can read their OWN audit log entry", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/auditLog/log_1`), {
        userId: "faculty_1",
        module: "courseworkItems",
        action: "create",
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/auditLog/log_1`)));
  });

  test("a faculty member CANNOT read someone else's audit log entry", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/auditLog/log_2`), {
        userId: "faculty_2",
        module: "courseworkItems",
        action: "create",
      });
    });
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/auditLog/log_2`)));
  });
});
