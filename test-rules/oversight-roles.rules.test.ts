import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

/**
 * Director and Principal supervise; Admin operates.
 *
 * The individual module suites each check their own collection. This one
 * exists because the rule is about the *shape* of the whole file: neither
 * oversight role may appear in an operational write anywhere, and the
 * four things they do keep have to keep working. A model asserted only
 * collection by collection is a model that comes apart one collection at
 * a time.
 */
let testEnv: RulesTestEnvironment;
const SCHOOL = "school_oversight";

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

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}`), {name: "San Nicolas Academy"});
    await setDoc(doc(db, `schools/${SCHOOL}/programs/prog_1`), {
      name: "BS Computer Science",
      createdBy: "admin_1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/teacherAssignments/ta_1`), {
      teacherId: "faculty_1",
      section: "Grade 10 - Rizal",
      createdBy: "admin_1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/expenses/exp_1`), {
      category: "Utilities",
      amount: 1000,
      createdBy: "admin_1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/inventory/item_1`), {
      name: "Projector",
      quantityOnHand: 0,
      createdBy: "admin_1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/feeStructures/fee_1`), {name: "Grade 10"});
    await setDoc(doc(db, `schools/${SCHOOL}/receiptBooklets/bk_1`), {series: "A"});
    await setDoc(doc(db, `schools/${SCHOOL}/users/faculty_1`), {
      role: "faculty",
      status: "active",
      firstName: "Maria",
    });
    // A top-level collection keyed by the employee's uid, not a
    // subcollection under their user document.
    await setDoc(doc(db, `schools/${SCHOOL}/compensation/faculty_1`), {rate: 30000});
    await setDoc(doc(db, `schools/${SCHOOL}/approvals/req_1`), {
      type: "material_request",
      requestedByRole: "staff",
      status: "pending",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/announcements/ann_1`), {
      title: "Notice",
      body: "Body",
      createdBy: "director_1",
      createdByName: "Ramon Valdez",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/meetings/meet_1`), {
      title: "Faculty meeting",
      createdBy: "director_1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/students/stu_1`), {
      firstName: "Miguel",
      educationLevel: "high_school",
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/guidanceRecords/gr_1`), {
      studentId: "stu_1",
      note: "Spoke with the class adviser.",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/summons/sum_1`), {
      studentId: "stu_1",
      reason: "Attendance",
      status: "pending",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/courseworkItems/cw_1`), {
      teacherId: "faculty_1",
      title: "Quiz 1",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/ec_1`), {
      label: "Clinic",
      phone: "0917 555 0100",
      sortOrder: 1,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
      employeeUid: "faculty_1",
      status: "pending",
      days: 2,
      fromDate: "2026-03-02",
      toDate: "2026-03-03",
      decidedByUid: null,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
      studentId: "stu_1",
      userId: "student_1",
      section: "Grade 10 - Rizal",
      raisedAt: new Date("2026-06-01T09:00:00Z"),
    });
  });
}

/** Every operational write, as one table. */
const OPERATIONAL: {what: string; path: string; patch: Record<string, unknown>}[] = [
  {what: "the school's own branding", path: "", patch: {logoUrl: "x"}},
  {what: "a program", path: "/programs/prog_1", patch: {name: "Renamed"}},
  {what: "a teacher assignment", path: "/teacherAssignments/ta_1", patch: {section: "Grade 9"}},
  {what: "an expense", path: "/expenses/exp_1", patch: {amount: 2000}},
  {what: "a stock item", path: "/inventory/item_1", patch: {reorderLevel: 5}},
  {what: "a fee schedule", path: "/feeStructures/fee_1", patch: {name: "Renamed"}},
  {what: "a receipt booklet", path: "/receiptBooklets/bk_1", patch: {series: "B"}},
  {what: "somebody's pay", path: "/compensation/faculty_1", patch: {rate: 99000}},
  {what: "another person's profile", path: "/users/faculty_1", patch: {firstName: "Renamed"}},
  {what: "a student record", path: "/students/stu_1", patch: {firstName: "Renamed"}},
  {what: "a guidance note", path: "/guidanceRecords/gr_1", patch: {note: "Rewritten."}},
  {what: "a summons", path: "/summons/sum_1", patch: {reason: "Rewritten"}},
  {what: "a piece of coursework", path: "/courseworkItems/cw_1", patch: {title: "Renamed"}},
  {what: "the school's emergency numbers", path: "/emergencyContacts/ec_1", patch: {phone: "0917 555 0999"}},
];

describe("what the two oversight roles may no longer change", () => {
  for (const role of ["director", "principal"]) {
    for (const {what, path} of OPERATIONAL) {
      it(`a ${role} cannot edit ${what}`, async () => {
        await seed();
        const db = contextAs(role).firestore();
        const target = OPERATIONAL.find((o) => o.what === what)!;
        await assertFails(
          updateDoc(doc(db, `schools/${SCHOOL}${path}`), target.patch as never)
        );
      });
    }
  }

  it("and the admin can edit every one of them", async () => {
    await seed();
    const db = contextAs("admin").firestore();
    for (const {what, path, patch} of OPERATIONAL) {
      await assertSucceeds(
        updateDoc(doc(db, `schools/${SCHOOL}${path}`), patch as never)
      ).catch((error) => {
        throw new Error(`admin should be able to edit ${what}: ${error}`);
      });
    }
  });
});

describe("what they may still read", () => {
  // Taking the buttons away is the point. Taking the visibility away
  // would defeat it: a supervisor who cannot see the records cannot
  // supervise.
  it("a director still reads what they can no longer change", async () => {
    await seed();
    const db = contextAs("director").firestore();
    for (const path of [
      "/programs/prog_1",
      "/teacherAssignments/ta_1",
      "/expenses/exp_1",
      "/inventory/item_1",
      "/feeStructures/fee_1",
      "/receiptBooklets/bk_1",
      "/compensation/faculty_1",
    ]) {
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}${path}`)));
    }
  });
});

describe("the four things they keep", () => {
  it("but not a leave request -- that went to the Admin as well", async () => {
    await seed();
    for (const role of ["director", "principal"]) {
      const db = contextAs(role).firestore();
      await assertFails(
        updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
          status: "approved",
          decidedByUid: `${role}_1`,
          decidedByName: "The Office",
          decidedByRole: role,
          decidedAt: new Date(),
          decisionRemarks: "Get well",
          updatedAt: new Date(),
          updatedBy: `${role}_1`,
        })
      );
    }
  });

  it("though they still read the queue", async () => {
    await seed();
    const db = contextAs("director").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`)));
  });

  it("a director decides an approval request", async () => {
    await seed();
    const db = contextAs("director").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/approvals/req_1`), {
        status: "approved",
        decidedByUid: "director_1",
        decidedByRole: "director",
      })
    );
  });

  it("a principal decides one too", async () => {
    await seed();
    const db = contextAs("principal").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/approvals/req_1`), {
        status: "rejected",
        decidedByUid: "principal_1",
        decidedByRole: "principal",
      })
    );
  });

  it("a director posts an announcement, as themselves", async () => {
    await seed();
    const db = contextAs("director").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/announcements/ann_2`), {
        title: "Classes suspended",
        body: "Typhoon signal 2.",
        createdBy: "director_1",
      })
    );
  });

  it("a principal calls a meeting", async () => {
    await seed();
    const db = contextAs("principal").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/meetings/meet_2`), {
        title: "Division heads",
        createdBy: "principal_1",
      })
    );
  });

  it("a director picks up an emergency alert", async () => {
    await seed();
    const db = contextAs("director").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
        acknowledgedBy: "director_1",
        acknowledgedByName: "Ramon Valdez",
        acknowledgedAt: new Date(),
      })
    );
  });
});
