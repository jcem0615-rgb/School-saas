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

    // Gate attendance. `personId` is a students/{id} for a child and an
    // auth uid for a member of staff, which is why the scoping has to
    // read `personRole` before it reads anything else.
    await setDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_shs_student`), {
      personId: "shs_student",
      personRole: "student",
      date: "2026-03-03",
      status: "late",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_jhs_student`), {
      personId: "jhs_student",
      personRole: "student",
      date: "2026-03-03",
      status: "present",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_faculty_eng`), {
      personId: "faculty_eng",
      personRole: "faculty",
      date: "2026-03-03",
      status: "present",
    });
    // A child scanned before Student Registration has made their
    // academic record: markAttendance falls back to the account id, so
    // there is no students/{id} to scope by.
    await setDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_acct_only`), {
      personId: "acct_only",
      personRole: "student",
      date: "2026-03-03",
      status: "present",
    });

    // The per-subject register.
    await setDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/mark_shs`), {
      sessionId: "2026-03-03_blk",
      studentId: "shs_student",
      subject: "Physics",
      status: "absent",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/mark_jhs`), {
      sessionId: "2026-03-03_blk",
      studentId: "jhs_student",
      subject: "Physics",
      status: "present",
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

describe("attendance is scoped the same way the rest of a student's file is", () => {
  test("a Junior High teacher CANNOT read a Senior High student's gate attendance", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertFails(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-03-03_shs_student`))
    );
  });

  test("the same teacher CAN read their own division's", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertSucceeds(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-03-03_jhs_student`))
    );
  });

  test("and CANNOT read the Senior High student's mark in a lesson either", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertFails(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/subjectAttendance/mark_shs`))
    );
  });

  test("but CAN read the mark for a student in their own division", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertSucceeds(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/subjectAttendance/mark_jhs`))
    );
  });

  test("a staff attendance row has no division, so scoping does not hide it", async () => {
    await seed();
    // The scan is a colleague's timekeeping, not a child's file. Refusing
    // it here would be scoping on a field that is not there -- and the
    // rule would have to fetch a students/{id} that does not exist to
    // find that out.
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertSucceeds(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-03-03_faculty_eng`))
    );
  });

  test("a child scanned before their academic record exists is still readable", async () => {
    await seed();
    const faculty = contextAs("faculty", "faculty_jhs");
    await assertSucceeds(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/attendance/2026-03-03_acct_only`))
    );
  });

  test("an unrestricted registrar reads every division, as before", async () => {
    await seed();
    const db = contextAs("registrar", "registrar_unrestricted").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_shs_student`)));
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_jhs_student`)));
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/mark_shs`)));
  });

  test("the director stays cross-division", async () => {
    await seed();
    const db = contextAs("director", "director_1").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/attendance/2026-03-03_shs_student`)));
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/subjectAttendance/mark_shs`)));
  });
});
