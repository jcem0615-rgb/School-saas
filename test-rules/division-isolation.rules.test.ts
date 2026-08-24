import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_division_test";

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
    // One firestore() handle per callback: calling context.firestore()
    // again after a write has started the instance throws
    // "Firestore has already been started and its settings can no longer
    // be changed", failing the test for a reason unrelated to rules.
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });

    // An elementary student and a college student (two different departments).
    await setDoc(doc(db, `schools/${SCHOOL}/students/elem_student`), {
      id: "elem_student",
      educationLevel: "elementary",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/college_eng_student`), {
      id: "college_eng_student",
      educationLevel: "college",
      department: "College of Engineering",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/college_biz_student`), {
      id: "college_biz_student",
      educationLevel: "college",
      department: "College of Business",
    });

    // A Senior High student. Making Senior High its own division is only
    // worth anything if the isolation rules actually treat it as one --
    // that is what the tests below check.
    await setDoc(doc(db, `schools/${SCHOOL}/students/shs_student`), {
      id: "shs_student",
      educationLevel: "senior_high",
      department: "Academic",
    });
    // A Junior High student, to prove the two do not bleed into each other.
    await setDoc(doc(db, `schools/${SCHOOL}/students/jhs_student`), {
      id: "jhs_student",
      educationLevel: "high_school",
    });

    // Registrar scoped to Elementary only.
    await setDoc(doc(db, `schools/${SCHOOL}/users/registrar_elem`), {
      role: "registrar",
      employeeInfo: {assignedDivision: "elementary"},
    });
    // Registrar with no configured scope -- should remain unrestricted.
    await setDoc(doc(db, `schools/${SCHOOL}/users/registrar_unrestricted`), {
      role: "registrar",
      employeeInfo: {department: "Registrar's Office", position: "Registrar"},
    });
    // Faculty scoped to Junior High. Before Senior High was split out,
    // "high_school" covered Grades 7-12, so this account would have seen
    // Senior High records too.
    await setDoc(doc(db, `schools/${SCHOOL}/users/faculty_jhs`), {
      role: "faculty",
      employeeInfo: {assignedDivision: "high_school"},
    });
    // Faculty scoped to College + College of Engineering specifically.
    await setDoc(doc(db, `schools/${SCHOOL}/users/faculty_eng`), {
      role: "faculty",
      employeeInfo: {assignedDivision: "college", assignedDepartment: "College of Engineering"},
    });

    await setDoc(doc(db, `schools/${SCHOOL}/grades/grade_eng`), {
      studentId: "college_eng_student",
      subject: "Calculus",
      score: 90,
      maxScore: 100,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/grades/grade_biz`), {
      studentId: "college_biz_student",
      subject: "Marketing",
      score: 88,
      maxScore: 100,
    });
  });
}

describe("division-scoped registrar", () => {
  test("CANNOT read a College student's record", async () => {
    await seed();
    const registrar = contextAs("registrar", "registrar_elem");
    await assertFails(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/college_eng_student`)));
  });

  test("CAN read an Elementary student's record", async () => {
    await seed();
    const registrar = contextAs("registrar", "registrar_elem");
    await assertSucceeds(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/elem_student`)));
  });
});

describe("Senior High is a division of its own", () => {
  test("a Junior High teacher CANNOT read a Senior High student", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/students/shs_student`)));
  });

  test("a Junior High teacher CAN still read their own division", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/students/jhs_student`)));
  });

  test("an Elementary registrar CANNOT read a Senior High student either", async () => {
    await seed();
    const registrar = contextAs("registrar", "registrar_elem");
    await assertFails(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/students/shs_student`)));
  });
});

describe("unrestricted registrar (assignedDivision never set) -- backward compatibility", () => {
  test("CAN read students in every division, unchanged from before this feature existed", async () => {
    await seed();
    const registrar = contextAs("registrar", "registrar_unrestricted");
    const registrarDb = registrar.firestore();
    await assertSucceeds(getDoc(doc(registrarDb, `schools/${SCHOOL}/students/elem_student`)));
    await assertSucceeds(getDoc(doc(registrarDb, `schools/${SCHOOL}/students/college_eng_student`)));
    await assertSucceeds(getDoc(doc(registrarDb, `schools/${SCHOOL}/students/college_biz_student`)));
  });
});

describe("department-scoped College faculty", () => {
  test("CAN read grades for a student in their own department (Engineering)", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_eng");
    await assertSucceeds(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/grades/grade_eng`)));
  });

  test("CANNOT read grades for a student in a different department (Business), same division", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_eng");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/grades/grade_biz`)));
  });

  test("CANNOT read an Elementary student's record (wrong division entirely)", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_eng");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/students/elem_student`)));
  });
});

describe("Director/Admin remain cross-division by design", () => {
  test("director can read students in every division regardless of any staff scoping", async () => {
    await seed();
    const director = contextAs("director", "director_1");
    const directorDb = director.firestore();
    await assertSucceeds(getDoc(doc(directorDb, `schools/${SCHOOL}/students/elem_student`)));
    await assertSucceeds(getDoc(doc(directorDb, `schools/${SCHOOL}/students/college_eng_student`)));
    await assertSucceeds(getDoc(doc(directorDb, `schools/${SCHOOL}/students/college_biz_student`)));
  });
});
