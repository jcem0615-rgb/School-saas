import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, addDoc, collection, serverTimestamp} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_emergency_test";
const LAPSED = "school_emergency_lapsed";

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

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    // A school whose subscription has lapsed. Still full of children.
    await setDoc(doc(db, `platform_subscriptions/${LAPSED}`), {
      schoolId: LAPSED,
      currentStatus: "suspended",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/users/parent_a`), {
      role: "parent",
      status: "active",
      linkedStudentIds: ["stu_a"],
    });
    await setDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/bfp`), {
      label: "BFP - San Nicolas",
      phone: "(043) 555 0161",
      sortOrder: 1,
      isDeleted: false,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
      studentId: "stu_a",
      studentName: "Miguel Torres",
      section: "Grade 10 - Rizal",
      userId: "student_a",
      raisedAt: new Date("2026-06-01T09:00:00Z"),
    });
  });
}

/**
 * The emergency collections are the two places in this schema where the
 * usual instinct -- scope it tightly -- is the wrong one. A number nobody
 * can read during a fire is not a safety feature, and an alert dropped
 * because a school is behind on its bill is indefensible.
 */
describe("emergency numbers", () => {
  test("every role in the school CAN read them", async () => {
    await seed();
    for (const role of ["student", "parent", "faculty", "staff", "guidance", "registrar", "admin"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/bfp`)));
    }
  });

  test("a student CANNOT edit them", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/bfp`), {phone: "000"})
    );
  });

  test("a faculty member CANNOT edit them either", async () => {
    // Not hostile -- a teacher fixing a wrong number sounds helpful. But
    // the list is what the whole school dials in a crisis, so it stays
    // with the roles accountable for it.
    await seed();
    const db = contextAs("faculty", "faculty_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/bfp`), {phone: "000"})
    );
  });

  test("an admin CAN maintain them", async () => {
    await seed();
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/pnp`), {
        label: "PNP - San Nicolas",
        phone: "(043) 555 0117",
        sortOrder: 2,
        isDeleted: false,
      })
    );
  });

  test("nobody outside the school can read them", async () => {
    await seed();
    const db = contextAs("admin", "outsider", "some_other_school").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/emergencyContacts/bfp`)));
  });
});

describe("raising an alert", () => {
  test("a student CAN raise one as themselves", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(
      addDoc(collection(db, `schools/${SCHOOL}/emergencyAlerts`), {
        studentId: "stu_a",
        studentName: "Miguel Torres",
        section: "Grade 10 - Rizal",
        userId: "student_a",
        raisedAt: serverTimestamp(),
      })
    );
  });

  test("a student CANNOT raise one in somebody else's name", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      addDoc(collection(db, `schools/${SCHOOL}/emergencyAlerts`), {
        studentId: "stu_b",
        studentName: "Someone Else",
        section: "Grade 10 - Rizal",
        userId: "student_b",
        raisedAt: serverTimestamp(),
      })
    );
  });

  test("a student CANNOT backdate one", async () => {
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      addDoc(collection(db, `schools/${SCHOOL}/emergencyAlerts`), {
        studentId: "stu_a",
        userId: "student_a",
        raisedAt: new Date("2020-01-01T00:00:00Z"),
      })
    );
  });

  test("an alert still goes through when the school's subscription has lapsed", async () => {
    // The single most important test in this file. Every other collection
    // in this app is gated on schoolIsAccessible(); this one deliberately
    // is not. A school behind on its bill still has children in it, and
    // billing is not a reason to drop an emergency alert on the floor.
    await seed();
    const db = contextAs("student", "student_lapsed", LAPSED).firestore();
    await assertSucceeds(
      addDoc(collection(db, `schools/${LAPSED}/emergencyAlerts`), {
        studentId: "stu_lapsed",
        userId: "student_lapsed",
        raisedAt: serverTimestamp(),
      })
    );
  });
});

describe("who sees and handles an alert", () => {
  test("staff CAN read it", async () => {
    await seed();
    for (const role of ["faculty", "guidance", "admin", "principal"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`)));
    }
  });

  test("the linked parent CAN read it", async () => {
    await seed();
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`)));
  });

  test("an unrelated student CANNOT read it", async () => {
    await seed();
    const db = contextAs("student", "student_b").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`)));
  });

  test("staff CAN acknowledge and resolve", async () => {
    await seed();
    const db = contextAs("faculty", "faculty_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
        acknowledgedByName: "Maria Santos",
        acknowledgedAt: serverTimestamp(),
      })
    );
  });

  test("staff CANNOT rewrite what the student said", async () => {
    // Handling an alert must not be a route to editing the report.
    await seed();
    const db = contextAs("faculty", "faculty_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
        message: "never mind, it was nothing",
      })
    );
  });

  test("the student who raised it CANNOT retract it", async () => {
    // An alert that can be quietly withdrawn is worth less than one that
    // cannot -- including when the pressure to withdraw comes from
    // someone else.
    await seed();
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/emergencyAlerts/alert_1`), {
        resolvedAt: serverTimestamp(),
      })
    );
  });
});
