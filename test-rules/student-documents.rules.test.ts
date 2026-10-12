import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_documents_test";

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

/** A folder row as the datasource writes one. */
function folderRow(overrides: Record<string, unknown> = {}) {
  return {
    studentId: "student_hs",
    studentName: "Juan Dela Cruz",
    kind: "birth_certificate",
    origin: "received",
    title: "PSA Birth Certificate",
    fileName: "psa.pdf",
    url: "https://example.test/psa.pdf",
    contentType: "application/pdf",
    sizeBytes: 2048,
    note: null,
    releaseId: null,
    filedByName: "Rosario Aguilar",
    filedBy: "registrar_1",
    filedAt: new Date(),
    archivedAt: null,
    archivedByName: null,
    archiveReason: null,
    schoolId: SCHOOL,
    createdBy: "registrar_1",
    createdAt: new Date(),
    isDeleted: false,
    ...overrides,
  };
}

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: a second context.firestore()
    // after a write throws "Firestore has already been started".
    const db = context.firestore();

    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });

    // A high school student with a portal account of their own, and a
    // college student in a department -- the pair the division scoping
    // is actually about.
    await setDoc(doc(db, `schools/${SCHOOL}/students/student_hs`), {
      id: "student_hs",
      userId: "student_user_1",
      educationLevel: "high_school",
      department: null,
      firstName: "Juan",
      lastName: "Dela Cruz",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/student_college`), {
      id: "student_college",
      userId: null,
      educationLevel: "college",
      department: "engineering",
      firstName: "Andrea",
      lastName: "Villanueva",
    });

    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_1`), {
      id: "parent_1",
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["student_hs"],
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_other`), {
      id: "parent_other",
      schoolId: SCHOOL,
      role: "parent",
      linkedStudentIds: ["student_college"],
    });

    // A registrar who covers high school only.
    await setDoc(doc(db, `schools/${SCHOOL}/users/registrar_hs`), {
      id: "registrar_hs",
      schoolId: SCHOOL,
      role: "registrar",
      employeeInfo: {assignedDivision: "high_school", assignedDepartment: null},
    });
    // ...and one with no scope at all, which is the ordinary case.
    await setDoc(doc(db, `schools/${SCHOOL}/users/registrar_1`), {
      id: "registrar_1",
      schoolId: SCHOOL,
      role: "registrar",
    });

    await setDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), folderRow());
    await setDoc(
      doc(db, `schools/${SCHOOL}/studentDocuments/doc_college`),
      folderRow({studentId: "student_college", studentName: "Andrea Villanueva"}),
    );
  });
}

describe("filing a document", () => {
  test("a registrar can file one", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(
      setDoc(
        doc(registrar.firestore(), `schools/${SCHOOL}/studentDocuments/doc_new`),
        folderRow(),
      ),
    );
  });

  test("the filer cannot be somebody else", async () => {
    // A folder entry naming another person as the one who filed it would
    // be worse than no entry: it puts a colleague's name on a decision
    // they did not make.
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      setDoc(
        doc(registrar.firestore(), `schools/${SCHOOL}/studentDocuments/doc_forged`),
        folderRow({filedBy: "registrar_hs", filedByName: "Someone Else"}),
      ),
    );
  });

  test("faculty cannot file into a student folder", async () => {
    // A teacher has no business adding to a child's civil-registry
    // folder, and this is the rule that says so rather than the absence
    // of a button.
    await seedFixtures();
    const teacher = contextAs("faculty", "teacher_1");
    await assertFails(
      setDoc(
        doc(teacher.firestore(), `schools/${SCHOOL}/studentDocuments/doc_teacher`),
        folderRow({filedBy: "teacher_1", filedByName: "Maria Santos"}),
      ),
    );
  });

  test("a parent cannot file into their own child's folder", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_1");
    await assertFails(
      setDoc(
        doc(parent.firestore(), `schools/${SCHOOL}/studentDocuments/doc_parent`),
        folderRow({filedBy: "parent_1", filedByName: "Lourdes"}),
      ),
    );
  });

  test("a registrar scoped to high school cannot file for a college student", async () => {
    await seedFixtures();
    const db = contextAs("registrar", "registrar_hs").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/studentDocuments/doc_oos`),
        folderRow({
          studentId: "student_college",
          filedBy: "registrar_hs",
          filedByName: "HS Registrar",
        }),
      ),
    );
    // ...and can for one in their own division.
    await assertSucceeds(
      setDoc(
        doc(db, `schools/${SCHOOL}/studentDocuments/doc_in_scope`),
        folderRow({filedBy: "registrar_hs", filedByName: "HS Registrar"}),
      ),
    );
  });
});

describe("reading a folder", () => {
  test("the office can read it", async () => {
    await seedFixtures();
    for (const role of ["registrar", "admin", "director", "principal"]) {
      const db = contextAs(role, `${role}_reader`).firestore();
      await assertSucceeds(
        getDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`)),
      );
    }
  });

  test("the student can read their own folder", async () => {
    // It is their birth certificate. A family that cannot see which of
    // their papers the school holds has to phone up to ask.
    await seedFixtures();
    const student = contextAs("student", "student_user_1");
    await assertSucceeds(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );
  });

  test("a student cannot read another student's folder", async () => {
    await seedFixtures();
    const student = contextAs("student", "student_user_1");
    await assertFails(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/studentDocuments/doc_college`)),
    );
  });

  test("a linked parent can read it, an unlinked one cannot", async () => {
    await seedFixtures();
    const parentDb = contextAs("parent", "parent_1").firestore();
    await assertSucceeds(
      getDoc(doc(parentDb, `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );

    const otherDb = contextAs("parent", "parent_other").firestore();
    await assertFails(
      getDoc(doc(otherDb, `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );
  });

  test("faculty cannot read a student folder", async () => {
    await seedFixtures();
    const teacher = contextAs("faculty", "teacher_1");
    await assertFails(
      getDoc(doc(teacher.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );
  });

  test("another school cannot read it", async () => {
    await seedFixtures();
    const outsider = testEnv.authenticatedContext("registrar_elsewhere", {
      schoolId: "some_other_school",
      role: "registrar",
      status: "active",
    });
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );
  });

  test("a registrar scoped to high school cannot read a college folder", async () => {
    await seedFixtures();
    const db = contextAs("registrar", "registrar_hs").firestore();
    await assertSucceeds(
      getDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`)),
    );
    await assertFails(
      getDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_college`)),
    );
  });
});

describe("withdrawing a document", () => {
  test("a registrar can archive one, with a reason", async () => {
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertSucceeds(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Rosario Aguilar",
        archiveReason: "Superseded by the corrected PSA copy.",
      }),
    );
  });

  test("an archive with no reason is refused", async () => {
    // An archive with no reason is a delete with extra steps: nobody can
    // later say whether the paper was superseded or filed under the
    // wrong child.
    await seedFixtures();
    const registrar = contextAs("registrar", "registrar_1");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Rosario Aguilar",
        archiveReason: "",
      }),
    );
  });

  test("nothing else about the row can be edited", async () => {
    // Which student, which file and when it was filed are what make the
    // row evidence. An update that could rewrite the url would be a
    // different document wearing this one's history.
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();

    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        url: "https://example.test/substituted.pdf",
      }),
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        studentId: "student_college",
      }),
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Rosario Aguilar",
        archiveReason: "Superseded.",
        title: "Something else entirely",
      }),
    );
  });

  test("archiving twice is refused", async () => {
    // The second one would overwrite the first reason, which is the only
    // record of why the paper went.
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Rosario Aguilar",
        archiveReason: "Superseded by the corrected PSA copy.",
      }),
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Someone Else",
        archiveReason: "Changed my mind about the reason.",
      }),
    );
  });

  test("a parent cannot archive their child's document", async () => {
    await seedFixtures();
    const parent = contextAs("parent", "parent_1");
    await assertFails(
      updateDoc(doc(parent.firestore(), `schools/${SCHOOL}/studentDocuments/doc_hs`), {
        archivedAt: new Date(),
        archivedByName: "Lourdes",
        archiveReason: "I would rather the school did not hold this.",
      }),
    );
  });
});

describe("deleting", () => {
  test("nobody can delete a folder entry -- not even the Director", async () => {
    // The same argument that makes documentReleases append-only. A folder
    // that can be emptied answers nothing.
    await seedFixtures();
    for (const role of ["registrar", "admin", "director", "principal"]) {
      const db = contextAs(role, `${role}_deleter`).firestore();
      await assertFails(
        deleteDoc(doc(db, `schools/${SCHOOL}/studentDocuments/doc_hs`)),
      );
    }
  });
});
