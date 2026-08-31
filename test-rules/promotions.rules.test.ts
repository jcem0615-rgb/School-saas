import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, updateDoc} from "firebase/firestore";

/**
 * The year-end rollover's records.
 *
 * Two things have to hold. Client writes are denied outright: the
 * promotion record's existence is what stops a rollover running twice,
 * so a client that could create one could move a child up a year with
 * nothing checking, and a client that could delete one could run the
 * whole rollover a second time and put every student in the school two
 * years above where they belong.
 *
 * And the family can read their own. "Was I promoted" is a question a
 * student and their parents are entitled to the answer to, from the
 * record rather than by queueing at the counter.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_promotions_test";
const STUDENT = "stu_001";
const OTHER_STUDENT = "stu_002";

const PROMOTION = `schools/${SCHOOL}/promotions/2026-2027_${STUDENT}`;
const OTHER_PROMOTION = `schools/${SCHOOL}/promotions/2026-2027_${OTHER_STUDENT}`;
const SCHOOL_YEAR = `schools/${SCHOOL}/schoolYears/2026-2027`;

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

function contextAs(role: string, uid: string, schoolId = SCHOOL) {
  return testEnv.authenticatedContext(uid, {
    schoolId,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const promotion = (studentId = STUDENT) => ({
  id: `2026-2027_${studentId}`,
  schoolId: SCHOOL,
  schoolYear: "2026-2027",
  studentId,
  studentName: "Miguel Torres",
  recommended: "promoted",
  outcome: "promoted",
  fromGradeLevel: "Grade 9",
  toGradeLevel: "Grade 10",
  generalAverage: 88,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/${STUDENT}`), {
      id: STUDENT,
      userId: "student_a",
      gradeLevel: "Grade 9",
      section: "Grade 9 - Rizal",
      educationLevel: "high_school",
      status: "enrolled",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/${OTHER_STUDENT}`), {
      id: OTHER_STUDENT,
      userId: "student_b",
      gradeLevel: "Grade 9",
      section: "Grade 9 - Rizal",
      educationLevel: "high_school",
      status: "enrolled",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_a`), {
      role: "parent",
      linkedStudentIds: [STUDENT],
    });
    await setDoc(doc(db, PROMOTION), promotion());
    await setDoc(doc(db, OTHER_PROMOTION), promotion(OTHER_STUDENT));
    await setDoc(doc(db, SCHOOL_YEAR), {
      id: "2026-2027",
      schoolId: SCHOOL,
      rolledOverCount: 2,
    });
  });
}

beforeEach(seed);

describe("nobody writes a promotion from a client", () => {
  it("not a registrar, who runs the rollover", async () => {
    // They run it through the callable. A direct write would skip every
    // check the callable makes, including the one that stops a student
    // being promoted twice.
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/promotions/2026-2027_stu_999`), promotion("stu_999"))
    );
  });

  it("not a director", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(updateDoc(doc(db, PROMOTION), {outcome: "retained"}));
  });

  it("and nobody deletes one", async () => {
    // The record's existence is what makes re-running the rollover safe.
    // Deleting it is how a school would promote a child a second time.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(deleteDoc(doc(db, PROMOTION)));
  });

  it("nor writes the school-year record", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(updateDoc(doc(db, SCHOOL_YEAR), {rolledOverCount: 0}));
  });
});

describe("who may read a promotion", () => {
  it("the registrar's office", async () => {
    for (const role of ["director", "admin", "principal", "registrar"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, PROMOTION)));
    }
  });

  it("the student it is about", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(getDoc(doc(db, PROMOTION)));
  });

  it("but not another student's", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertFails(getDoc(doc(db, OTHER_PROMOTION)));
  });

  it("their parent", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(getDoc(doc(db, PROMOTION)));
  });

  it("but not a parent of a different child", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(getDoc(doc(db, OTHER_PROMOTION)));
  });

  it("not a teacher, who has no business in a promotion decision", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(getDoc(doc(db, PROMOTION)));
  });

  it("not somebody from another school", async () => {
    const db = contextAs("registrar", "registrar_b", "another_school").firestore();
    await assertFails(getDoc(doc(db, PROMOTION)));
  });
});

describe("the school-year record", () => {
  it("is readable by anyone in the school, since it is only counts", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(getDoc(doc(db, SCHOOL_YEAR)));
  });

  it("but not from another school", async () => {
    const db = contextAs("admin", "admin_b", "another_school").firestore();
    await assertFails(getDoc(doc(db, SCHOOL_YEAR)));
  });
});
