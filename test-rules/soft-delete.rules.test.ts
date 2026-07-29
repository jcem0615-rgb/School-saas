import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * Covers the edit + delete capability added across the portals.
 *
 * The central claim these tests exist to defend: **there is no hard delete
 * anywhere in this system.** Every collection sets `allow delete: if false`,
 * so "delete" in the UI is an update that sets `isDeleted`, and reads filter
 * on that flag. If someone later relaxes a delete rule to make a feature
 * easier, the `deleteDoc` assertions here fail and say so.
 *
 * The second claim: an edit cannot launder authorship or move a record to a
 * different owner. Each collection's update rule pins one field
 * (createdBy / teacherId / staffId / studentId) and those pins are tested
 * individually, because they are what stop an "edit" from becoming a
 * privilege escalation.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_softdelete_test";

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

async function seedActiveSubscription() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
  });
}

/** Writes a document bypassing rules, so tests start from a known state. */
async function seedDoc(path: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), {
      schoolId: SCHOOL,
      isDeleted: false,
      deletedAt: null,
      deletedBy: null,
      ...data,
    });
  });
}

/** The exact payload the app sends for a soft delete. */
const softDeletePayload = (uid: string) => ({
  isDeleted: true,
  deletedAt: new Date(),
  deletedBy: uid,
  updatedBy: uid,
  updatedAt: new Date(),
});

beforeEach(async () => {
  await seedActiveSubscription();
});

// ---------------------------------------------------------------------------
// Hard delete is denied everywhere -- the property the whole design rests on
// ---------------------------------------------------------------------------

describe("hard delete is denied on every content collection", () => {
  const collections = [
    "announcements",
    "meetings",
    "expenses",
    "teacherAssignments",
    "courseworkItems",
    "checklistItems",
    "guidanceRecords",
    "summons",
    "programs",
    "dailyReports",
  ];

  test.each(collections)("director cannot deleteDoc a %s", async (collection) => {
    await seedDoc(`schools/${SCHOOL}/${collection}/doc_1`, {
      createdBy: "director_1",
      teacherId: "director_1",
      staffId: "director_1",
      studentId: "stu_1",
    });
    const director = contextAs("director");
    await assertFails(
      deleteDoc(doc(director.firestore(), `schools/${SCHOOL}/${collection}/doc_1`))
    );
  });
});

// ---------------------------------------------------------------------------
// Soft delete + edit, per collection
// ---------------------------------------------------------------------------

describe("announcements", () => {
  const path = `schools/${SCHOOL}/announcements/ann_1`;

  test("director can soft delete", async () => {
    await seedDoc(path, {title: "T", body: "B", createdBy: "director_1"});
    const director = contextAs("director");
    await assertSucceeds(
      updateDoc(doc(director.firestore(), path), softDeletePayload("director_1"))
    );
  });

  test("faculty cannot soft delete", async () => {
    await seedDoc(path, {title: "T", body: "B", createdBy: "director_1"});
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), softDeletePayload("faculty_1"))
    );
  });

  test("director can edit the content", async () => {
    await seedDoc(path, {title: "T", body: "B", createdBy: "director_1"});
    const director = contextAs("director");
    await assertSucceeds(
      updateDoc(doc(director.firestore(), path), {
        title: "Edited",
        body: "Edited body",
        createdBy: "director_1",
        updatedBy: "director_1",
      })
    );
  });

  test("an edit cannot reassign authorship", async () => {
    await seedDoc(path, {title: "T", body: "B", createdBy: "director_1"});
    const admin = contextAs("admin");
    await assertFails(
      updateDoc(doc(admin.firestore(), path), {title: "Edited", createdBy: "admin_1"})
    );
  });
});

describe("meetings", () => {
  const path = `schools/${SCHOOL}/meetings/mtg_1`;

  test("director can soft delete", async () => {
    await seedDoc(path, {title: "T", createdBy: "director_1"});
    const director = contextAs("director");
    await assertSucceeds(
      updateDoc(doc(director.firestore(), path), softDeletePayload("director_1"))
    );
  });

  test("staff cannot soft delete", async () => {
    await seedDoc(path, {title: "T", createdBy: "director_1"});
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), path), softDeletePayload("staff_1"))
    );
  });
});

describe("expenses", () => {
  const path = `schools/${SCHOOL}/expenses/exp_1`;

  test("admin can soft delete", async () => {
    await seedDoc(path, {category: "Utilities", amount: 100, createdBy: "admin_1"});
    const admin = contextAs("admin");
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), path), softDeletePayload("admin_1"))
    );
  });

  test("registrar can read but cannot soft delete", async () => {
    await seedDoc(path, {category: "Utilities", amount: 100, createdBy: "admin_1"});
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), path), softDeletePayload("registrar_1"))
    );
  });
});

describe("courseworkItems", () => {
  const path = `schools/${SCHOOL}/courseworkItems/cw_1`;

  test("the owning teacher can soft delete their own item", async () => {
    await seedDoc(path, {title: "T", teacherId: "faculty_1", published: true});
    const faculty = contextAs("faculty");
    await assertSucceeds(
      updateDoc(doc(faculty.firestore(), path), softDeletePayload("faculty_1"))
    );
  });

  test("a different teacher cannot soft delete someone else's item", async () => {
    await seedDoc(path, {title: "T", teacherId: "faculty_other", published: true});
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), softDeletePayload("faculty_1"))
    );
  });

  test("an edit cannot reassign the item to the editor", async () => {
    await seedDoc(path, {title: "T", teacherId: "faculty_1", published: true});
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), {title: "Edited", teacherId: "faculty_1_stolen"})
    );
  });
});

describe("checklistItems", () => {
  const path = `schools/${SCHOOL}/checklistItems/chk_1`;

  test("staff can soft delete their own task", async () => {
    await seedDoc(path, {task: "Sweep", staffId: "staff_1", completed: false});
    const staff = contextAs("staff");
    await assertSucceeds(
      updateDoc(doc(staff.firestore(), path), softDeletePayload("staff_1"))
    );
  });

  test("staff cannot soft delete another staff member's task", async () => {
    await seedDoc(path, {task: "Sweep", staffId: "staff_other", completed: false});
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), path), softDeletePayload("staff_1"))
    );
  });
});

describe("guidanceRecords", () => {
  const path = `schools/${SCHOOL}/guidanceRecords/gui_1`;

  test("guidance can soft delete", async () => {
    await seedDoc(path, {studentId: "stu_1", notes: "n", category: "academic"});
    const guidance = contextAs("guidance");
    await assertSucceeds(
      updateDoc(doc(guidance.firestore(), path), {
        ...softDeletePayload("guidance_1"),
        studentId: "stu_1",
      })
    );
  });

  test("faculty cannot soft delete a counseling note", async () => {
    await seedDoc(path, {studentId: "stu_1", notes: "n", category: "academic"});
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), {
        ...softDeletePayload("faculty_1"),
        studentId: "stu_1",
      })
    );
  });

  test("an edit cannot move a note to a different student", async () => {
    await seedDoc(path, {studentId: "stu_1", notes: "n", category: "academic"});
    const guidance = contextAs("guidance");
    await assertFails(
      updateDoc(doc(guidance.firestore(), path), {notes: "edited", studentId: "stu_2"})
    );
  });
});

describe("summons", () => {
  const path = `schools/${SCHOOL}/summons/sum_1`;

  test("guidance can soft delete", async () => {
    await seedDoc(path, {studentId: "stu_1", reason: "r", status: "pending"});
    const guidance = contextAs("guidance");
    await assertSucceeds(
      updateDoc(doc(guidance.firestore(), path), {
        ...softDeletePayload("guidance_1"),
        studentId: "stu_1",
      })
    );
  });

  test("principal is read-only and cannot soft delete", async () => {
    await seedDoc(path, {studentId: "stu_1", reason: "r", status: "pending"});
    const principal = contextAs("principal");
    await assertFails(
      updateDoc(doc(principal.firestore(), path), {
        ...softDeletePayload("principal_1"),
        studentId: "stu_1",
      })
    );
  });
});

describe("programs", () => {
  const path = `schools/${SCHOOL}/programs/prog_1`;

  test("admin can soft delete", async () => {
    await seedDoc(path, {name: "BSCS", code: "BSCS", department: "CS"});
    const admin = contextAs("admin");
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), path), softDeletePayload("admin_1"))
    );
  });

  test("registrar cannot soft delete", async () => {
    await seedDoc(path, {name: "BSCS", code: "BSCS", department: "CS"});
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), path), softDeletePayload("registrar_1"))
    );
  });
});

describe("teacherAssignments", () => {
  const path = `schools/${SCHOOL}/teacherAssignments/ta_1`;

  test("admin can soft delete", async () => {
    await seedDoc(path, {subject: "Math", section: "10-A", createdBy: "admin_1"});
    const admin = contextAs("admin");
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), path), softDeletePayload("admin_1"))
    );
  });

  test("faculty cannot soft delete their own assignment record", async () => {
    await seedDoc(path, {subject: "Math", section: "10-A", createdBy: "admin_1", teacherId: "faculty_1"});
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), path), softDeletePayload("faculty_1"))
    );
  });
});

// ---------------------------------------------------------------------------
// dailyReports: deliberately immutable, and must stay that way
// ---------------------------------------------------------------------------

describe("dailyReports stay immutable", () => {
  const path = `schools/${SCHOOL}/dailyReports/rep_1`;

  // A daily work log is a point-in-time record; corrections are filed as a
  // new entry rather than an edit, so the history stays trustworthy. This is
  // why dailyReports is the one content collection with no edit or delete in
  // the UI -- these tests are what stop that from being "fixed" by accident.
  test("the author cannot edit their own submitted report", async () => {
    await seedDoc(path, {content: "original", staffId: "staff_1", date: "2026-01-01"});
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), path), {content: "rewritten", staffId: "staff_1"})
    );
  });

  test("even a director cannot edit a submitted report", async () => {
    await seedDoc(path, {content: "original", staffId: "staff_1", date: "2026-01-01"});
    const director = contextAs("director");
    await assertFails(
      updateDoc(doc(director.firestore(), path), {content: "rewritten", staffId: "staff_1"})
    );
  });

  test("a report cannot be soft deleted either", async () => {
    await seedDoc(path, {content: "original", staffId: "staff_1", date: "2026-01-01"});
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), path), {
        ...softDeletePayload("staff_1"),
        staffId: "staff_1",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// A suspended school is frozen, including deletions
// ---------------------------------------------------------------------------

describe("suspended schools cannot soft delete", () => {
  test("director cannot soft delete while the subscription is suspended", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
        schoolId: SCHOOL,
        currentStatus: "suspended",
      });
    });
    await seedDoc(`schools/${SCHOOL}/announcements/ann_1`, {
      title: "T",
      createdBy: "director_1",
    });
    const director = contextAs("director");
    await assertFails(
      updateDoc(
        doc(director.firestore(), `schools/${SCHOOL}/announcements/ann_1`),
        softDeletePayload("director_1")
      )
    );
  });
});
