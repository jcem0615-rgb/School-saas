import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, updateDoc, getDocs, collection} from "firebase/firestore";

/**
 * Admissions enquiries.
 *
 * This is the one collection in a tenant holding personal data about
 * people who have no relationship with the school at all -- a family who
 * rang once in February and enrolled somewhere else. So the read list is
 * the admissions office and nobody else, and writes go through the
 * callables, which are where the stage rules and the "enrolled exactly
 * once" guarantee live.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_applicants_test";
const APPLICANT = `schools/${SCHOOL}/applicants/app_001`;

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

const applicant = () => ({
  id: "app_001",
  schoolId: SCHOOL,
  referenceNumber: "A-2026-0001",
  firstName: "Bea",
  lastName: "Torres",
  educationLevel: "high_school",
  gradeLevel: "Grade 7",
  guardianName: "Rosario Torres",
  guardianPhone: "09171234567",
  stage: "inquiry",
  reservationFeePaid: 0,
  studentId: null,
  isDeleted: false,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, APPLICANT), applicant());
  });
}

beforeEach(seed);

describe("who may read an enquiry", () => {
  it("the admissions office", async () => {
    for (const role of ["director", "admin", "registrar"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, APPLICANT)));
    }
  });

  it("not a teacher", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(getDoc(doc(db, APPLICANT)));
  });

  it("not guidance, who read almost everything else about a child", async () => {
    // A guidance counsellor's scope is students at this school. An
    // applicant is not one, and may never be.
    const db = contextAs("guidance", "guidance_a").firestore();
    await assertFails(getDoc(doc(db, APPLICANT)));
  });

  it("not a principal", async () => {
    const db = contextAs("principal", "principal_a").firestore();
    await assertFails(getDoc(doc(db, APPLICANT)));
  });

  it("not a parent, and not a student", async () => {
    await assertFails(getDoc(doc(contextAs("parent", "parent_a").firestore(), APPLICANT)));
    await assertFails(getDoc(doc(contextAs("student", "student_a").firestore(), APPLICANT)));
  });

  it("not the registrar of another school", async () => {
    const db = contextAs("registrar", "registrar_b", "another_school").firestore();
    await assertFails(getDoc(doc(db, APPLICANT)));
  });

  it("and the list cannot be browsed by anyone outside the office", async () => {
    // Firestore rejects a query rather than filtering it, so this is the
    // check that actually matters for a screen that lists them.
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(getDocs(collection(db, `schools/${SCHOOL}/applicants`)));
  });
});

describe("nobody writes an enquiry from a client", () => {
  it("not a registrar, who takes them down all day", async () => {
    // They go through saveApplicant. A direct write would skip the stage
    // rules -- including the one that stops "enrolled" being set with no
    // student record behind it.
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/applicants/app_002`), applicant())
    );
  });

  it("not a director, and not by setting the stage directly", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(updateDoc(doc(db, APPLICANT), {stage: "enrolled"}));
  });

  it("and nobody deletes one", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(deleteDoc(doc(db, APPLICANT)));
  });
});
