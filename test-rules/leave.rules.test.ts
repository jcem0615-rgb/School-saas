import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc, getDocs, collection, query, where} from "firebase/firestore";

/**
 * Employee leave.
 *
 * Two things have to hold. An employee files only for themselves and
 * only as undecided -- a request that could arrive pre-approved makes
 * the decision step decorative. And a decision carries the decider's own
 * uid, so the name beside "approved" is the account that approved it.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_leave_test";

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

const filed = (overrides: Record<string, unknown> = {}) => ({
  id: "lv_1",
  schoolId: SCHOOL,
  employeeUid: "staff_a",
  employeeName: "Ana Cruz",
  employeeRole: "staff",
  type: "sick",
  fromDate: "2026-03-03",
  toDate: "2026-03-04",
  days: 2,
  reason: "Fever",
  status: "pending",
  decidedByUid: null,
  decidedByName: null,
  decidedByRole: null,
  decidedAt: null,
  decisionRemarks: null,
  createdAt: new Date("2026-03-01T01:00:00Z"),
  createdBy: "staff_a",
  updatedAt: new Date("2026-03-01T01:00:00Z"),
  updatedBy: "staff_a",
  deletedAt: null,
  deletedBy: null,
  isDeleted: false,
  ...overrides,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), filed());
  });
}

beforeEach(seed);

describe("filing", () => {
  it("an employee files for themselves", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_new`), filed({id: "lv_new"}))
    );
  });

  it("but not in a colleague's name", async () => {
    const db = contextAs("staff", "staff_b").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_new`), filed({id: "lv_new"}))
    );
  });

  it("and not already approved", async () => {
    // The one that makes the decision step mean anything.
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_new`),
        filed({id: "lv_new", status: "approved", decidedByUid: "admin_a"})
      )
    );
  });

  it("with a range that runs forwards and a day count above zero", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_bad`),
        filed({id: "lv_bad", fromDate: "2026-03-09", toDate: "2026-03-02"})
      )
    );
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_zero`),
        filed({id: "lv_zero", days: 0})
      )
    );
  });

  it("is not something a student or a parent can do", async () => {
    for (const [role, uid] of [
      ["student", "student_a"],
      ["parent", "parent_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        setDoc(
          doc(db, `schools/${SCHOOL}/leaveRequests/lv_${uid}`),
          filed({id: `lv_${uid}`, employeeUid: uid, employeeRole: role})
        )
      );
    }
  });
});

describe("reading", () => {
  it("an employee reads their own", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`)));
  });

  it("and lists their own, filtered to themselves", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, `schools/${SCHOOL}/leaveRequests`),
          where("employeeUid", "==", "staff_a")
        )
      )
    );
  });

  it("but cannot list the school's", async () => {
    // A colleague's sick leave is not theirs to read, and an unfiltered
    // query is exactly the shape that would hand it to them.
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      getDocs(collection(db, `schools/${SCHOOL}/leaveRequests`))
    );
  });

  it("nor a colleague's by id", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`)));
  });

  it("the office reads all of it", async () => {
    for (const [role, uid] of [
      ["admin", "admin_a"],
      ["principal", "principal_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(
        getDocs(collection(db, `schools/${SCHOOL}/leaveRequests`))
      );
    }
  });
});

describe("deciding", () => {
  const decision = (uid: string, role: string, status = "approved") => ({
    status,
    decidedByUid: uid,
    decidedByName: "The Office",
    decidedByRole: role,
    decidedAt: new Date("2026-03-02T01:00:00Z"),
    decisionRemarks: "Get well",
    updatedAt: new Date("2026-03-02T01:00:00Z"),
    updatedBy: uid,
  });

  it("the office approves or declines", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      updateDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`),
        decision("admin_a", "admin")
      )
    );
  });

  it("but cannot record the decision under somebody else's name", async () => {
    // Without this the approval history is a field anybody can type into.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`),
        decision("director_a", "director")
      )
    );
  });

  it("nor claim a role they do not hold", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`),
        decision("admin_a", "director")
      )
    );
  });

  it("the employee cannot approve their own", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      updateDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`),
        decision("staff_a", "staff")
      )
    );
  });

  it("a decision cannot quietly move the request to another employee", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        ...decision("admin_a", "admin"),
        employeeUid: "staff_b",
      })
    );
  });

  it("nor rewrite the dates it is approving", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        ...decision("admin_a", "admin"),
        toDate: "2026-03-20",
        days: 14,
      })
    );
  });

  it("an already-decided request is not decided again", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `schools/${SCHOOL}/leaveRequests/lv_1`),
        filed({status: "approved", decidedByUid: "admin_a"})
      );
    });
    const db = contextAs("director", "director_a").firestore();
    await assertFails(
      updateDoc(
        doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`),
        decision("director_a", "director", "declined")
      )
    );
  });
});

describe("withdrawing", () => {
  it("the employee withdraws their own pending request", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        status: "cancelled",
        updatedAt: new Date(),
        updatedBy: "staff_a",
      })
    );
  });

  it("and cannot change anything else on the way out", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        status: "cancelled",
        days: 10,
        updatedAt: new Date(),
        updatedBy: "staff_a",
      })
    );
  });

  it("a colleague cannot withdraw it for them", async () => {
    const db = contextAs("staff", "staff_b").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        status: "cancelled",
        updatedAt: new Date(),
        updatedBy: "staff_b",
      })
    );
  });

  it("an approved request cannot be withdrawn by the employee", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `schools/${SCHOOL}/leaveRequests/lv_1`),
        filed({status: "approved", decidedByUid: "admin_a"})
      );
    });
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`), {
        status: "cancelled",
        updatedAt: new Date(),
        updatedBy: "staff_a",
      })
    );
  });
});

describe("deleting", () => {
  it("nobody deletes a leave record", async () => {
    for (const [role, uid] of [
      ["staff", "staff_a"],
      ["admin", "admin_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        deleteDoc(doc(db, `schools/${SCHOOL}/leaveRequests/lv_1`))
      );
    }
  });
});
