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
  /**
   * A mark is server-written now, and these two tests are why.
   *
   * The old rules allowed a teacher to correct a score in place, and the
   * test below asserted it -- correctly, about the rules. But no code
   * path in the app ever issued that update: `submitGrade` wrote a new
   * document every time, and the quarterly arithmetic sums the scores
   * and the maximums inside a component, so a teacher fixing
   * 80-out-of-10 to 8-out-of-10 left the child on 88 out of 20. A rules
   * test proving a capability nothing exercises is the most comfortable
   * kind of wrong.
   *
   * `saveAssessmentScores` writes each mark at `{assessment}_{student}`,
   * so entering it again replaces it -- and the client writes none of
   * it, which also closes the hole the old update rule left open: it
   * pinned `studentId` and nothing else, so `submittedByName` was
   * writable and "who gave this grade" answered with whatever was typed.
   */
  test("no client may write a mark, whatever their role", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/grades/grade_1`), {
        studentId: "student_1",
        score: 90,
        maxScore: 100,
        submittedByName: "Ms Reyes",
      });
    });

    for (const [role, uid] of [
      ["faculty", "faculty_1"],
      ["director", "director_1"],
      ["admin", "admin_1"],
    ]) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        setDoc(doc(db, `schools/${SCHOOL}/grades/grade_new_${uid}`), {
          studentId: "student_1",
          score: 90,
          maxScore: 100,
        })
      );
      // Including the two the old rule left open: the score itself, and
      // the name against it.
      await assertFails(
        updateDoc(doc(db, `schools/${SCHOOL}/grades/grade_1`), {score: 88})
      );
      await assertFails(
        updateDoc(doc(db, `schools/${SCHOOL}/grades/grade_1`), {
          submittedByName: "Somebody Else",
        })
      );
    }
  });

  test("a teacher can still read the marks they gave", async () => {
    // Server-written does not mean invisible. The class record is a
    // read of these.
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      // One firestore() per context: calling it twice throws "settings
      // can no longer be changed".
      const db = context.firestore();
      await setDoc(doc(db, `schools/${SCHOOL}/students/student_1`), {
        id: "student_1",
        educationLevel: "high_school",
        isDeleted: false,
      });
      await setDoc(doc(db, `schools/${SCHOOL}/grades/grade_3`), {
        studentId: "student_1",
        score: 90,
        maxScore: 100,
      });
    });
    // A fresh uid: @firebase/rules-unit-testing caches a context per
    // uid, and calling firestore() on one already used in another test
    // throws "settings can no longer be changed".
    const faculty = contextAs("faculty", "faculty_reader");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/grades/grade_3`)));
  });
});

describe("the pieces of work behind a mark", () => {
  test("are readable by the school and written by nobody", async () => {
    // A student reading "18 out of 20" needs to know what the 20 was
    // for; a total editable from a console is a total the marks were
    // never checked against.
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `schools/${SCHOOL}/classAssessments/as_1`), {
        subject: "Mathematics",
        section: "Grade 10 - Rizal",
        term: "Q1",
        title: "Quiz 1",
        component: "written_work",
        maxScore: 20,
        isDeleted: false,
      });
      await setDoc(doc(db, `schools/${SCHOOL}/classWeights/mathematics__grade-10-rizal`), {
        subject: "Mathematics",
        section: "Grade 10 - Rizal",
        writtenWork: 40,
        performanceTask: 40,
        quarterlyAssessment: 20,
      });
    });

    for (const [role, uid] of [
      ["faculty", "faculty_work_reader"],
      ["student", "student_work_reader"],
      ["parent", "parent_work_reader"],
    ]) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/classAssessments/as_1`)));
      // How the number was reached is not a secret from the family.
      await assertSucceeds(
        getDoc(doc(db, `schools/${SCHOOL}/classWeights/mathematics__grade-10-rizal`))
      );
    }

    const faculty = contextAs("faculty", "faculty_work_writer").firestore();
    await assertFails(
      updateDoc(doc(faculty, `schools/${SCHOOL}/classAssessments/as_1`), {maxScore: 5})
    );
    await assertFails(
      updateDoc(doc(faculty, `schools/${SCHOOL}/classWeights/mathematics__grade-10-rizal`), {
        writtenWork: 90,
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
