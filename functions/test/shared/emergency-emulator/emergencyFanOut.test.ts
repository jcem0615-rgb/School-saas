/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/emergency-emulator"
 *
 * Who is told when a student presses the button.
 *
 * Two defects are pinned here, and both end the same way: an alert that
 * reaches nobody in the building.
 *
 * The adviser was found with `where("section", "==", ...)`. Section names
 * are typed by hand on the student record and again on the teacher's
 * assignment, so "Grade 10 - Rizal" against "Grade 10 - rizal " simply
 * found no adviser -- and no error, and no second recipient.
 *
 * And the adviser was the only member of staff told at all. A section
 * with none set, or one whose adviser has left, meant the alert went to
 * the child's parents and to nobody who was actually in the school.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_sos";
const RIZAL = "Grade 10 - Rizal";
const MABINI = "Grade 10 - Mabini";

/* eslint-disable @typescript-eslint/no-explicit-any */
let fanOut: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

async function clear(path: string) {
  const snap = await db().collection(path).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

/** Every uid that got an inbox item for this alert. */
async function told(alertId: string): Promise<string[]> {
  const itemId = `emergency_${alertId}`;
  const snap = await db().collectionGroup("items").get();
  return snap.docs
    .filter((d) => d.id === itemId && d.ref.path.startsWith(`schools/${SCHOOL}/`))
    // .../notifications/{uid}/items/{itemId}
    .map((d) => d.ref.path.split("/")[3])
    .sort();
}

/** Writes the alert and runs the trigger over it. */
async function raise(
  id: string,
  over: Record<string, unknown> = {}
): Promise<string[]> {
  const data = {
    id,
    schoolId: SCHOOL,
    studentId: "stu_rizal",
    studentName: "Miguel Torres",
    section: RIZAL,
    userId: "u_student_rizal",
    message: "I am hurt near the covered court.",
    ...over,
  };
  const path = `schools/${SCHOOL}/emergencyAlerts/${id}`;
  await db().doc(path).set(data);
  await fanOut({
    data: fft.firestore.makeDocumentSnapshot(data, path),
    params: {schoolId: SCHOOL, alertId: id},
  } as never);
  return told(id);
}

async function seed() {
  for (const path of [
    FirestorePaths.users(SCHOOL),
    FirestorePaths.teacherAssignments(SCHOOL),
    `schools/${SCHOOL}/emergencyAlerts`,
  ]) {
    await clear(path);
  }
  const stale = await db().collectionGroup("items").get();
  await Promise.all(
    stale.docs.filter((d) => d.ref.path.startsWith(`schools/${SCHOOL}/`)).map((d) => d.ref.delete())
  );

  const user = (id: string, role: string, over: Record<string, unknown> = {}) =>
    db().doc(FirestorePaths.userDoc(SCHOOL, id)).set({
      id,
      schoolId: SCHOOL,
      role,
      status: "active",
      firstName: id,
      lastName: "Test",
      isDeleted: false,
      ...over,
    });

  await Promise.all([
    user("u_student_rizal", "student"),
    user("u_parent_rizal", "parent", {linkedStudentIds: ["stu_rizal"]}),
    user("u_parent_mabini", "parent", {linkedStudentIds: ["stu_mabini"]}),
    user("u_adviser_rizal", "faculty"),
    user("u_adviser_mabini", "faculty"),
    user("u_subject_teacher", "faculty"),
    user("u_guidance", "guidance"),
    user("u_director", "director"),
    user("u_admin", "admin"),
    // Not a responder, and not in the class.
    user("u_registrar", "registrar"),
    // Has left. An account that cannot sign in has no inbox to read.
    user("u_guidance_gone", "guidance", {status: "inactive"}),
  ]);

  await Promise.all([
    // Typed differently from the alert on purpose. This is what a
    // school's data actually looks like.
    db().collection(FirestorePaths.teacherAssignments(SCHOOL)).doc("ta_adviser").set({
      teacherId: "u_adviser_rizal",
      teacherName: "Maria Santos",
      section: "  grade 10  -  rizal ",
      subject: "Mathematics",
      isAdviser: true,
    }),
    db().collection(FirestorePaths.teacherAssignments(SCHOOL)).doc("ta_subject").set({
      teacherId: "u_subject_teacher",
      teacherName: "Dennis Pascual",
      section: RIZAL,
      subject: "Science",
      isAdviser: false,
    }),
    db().collection(FirestorePaths.teacherAssignments(SCHOOL)).doc("ta_other").set({
      teacherId: "u_adviser_mabini",
      teacherName: "Ana Reyes",
      section: MABINI,
      subject: "English",
      isAdviser: true,
    }),
  ]);
}

describe("who is told about an emergency alert", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const mod = await import("../../../src/triggers/emergency/onEmergencyAlertCreated");
    fanOut = fft.wrap(mod.onEmergencyAlertCreated);
  });

  afterAll(() => {
    fft.cleanup();
  });

  beforeEach(seed);

  it("finds the adviser even though the section is spelt differently on their assignment", async () => {
    // The defect. An exact match found no adviser, said nothing about
    // it, and left the nearest member of staff untold.
    expect(await raise("alert_typed")).toContain("u_adviser_rizal");
  });

  it("tells guidance and the office as well, every time", async () => {
    // The adviser alone is one absence away from nobody.
    const reached = await raise("alert_responders");
    expect(reached).toContain("u_guidance");
    expect(reached).toContain("u_director");
    expect(reached).toContain("u_admin");
  });

  it("still tells the school when the section has no adviser at all", async () => {
    const reached = await raise("alert_noadviser", {section: "Grade 7 - Sampaguita"});
    expect(reached).toEqual(["u_admin", "u_director", "u_guidance", "u_parent_rizal"]);
  });

  it("tells the child's own parents and no other family", async () => {
    const reached = await raise("alert_family");
    expect(reached).toContain("u_parent_rizal");
    expect(reached).not.toContain("u_parent_mabini");
  });

  it("does not tell another class's adviser, or a subject teacher of this one", async () => {
    // The adviser is the one member of teaching staff responsible for
    // the class as a whole. Every teacher who takes them is a different
    // and much longer list.
    const reached = await raise("alert_scope");
    expect(reached).not.toContain("u_adviser_mabini");
    expect(reached).not.toContain("u_subject_teacher");
  });

  it("does not tell the registrar, who is not a responder", async () => {
    expect(await raise("alert_registrar")).not.toContain("u_registrar");
  });

  it("does not tell somebody who has left the school", async () => {
    expect(await raise("alert_leaver")).not.toContain("u_guidance_gone");
  });

  it("says who it is about, and what they said", async () => {
    await raise("alert_wording");
    const item = await db()
      .doc(`${FirestorePaths.school(SCHOOL)}/notifications/u_guidance/items/emergency_alert_wording`)
      .get();
    expect(item.data()!.title).toBe("Emergency alert: Miguel Torres");
    expect(item.data()!.body).toBe("I am hurt near the covered court.");
  });

  it("still says something useful when the student typed nothing", async () => {
    await raise("alert_silent", {message: ""});
    const item = await db()
      .doc(`${FirestorePaths.school(SCHOOL)}/notifications/u_guidance/items/emergency_alert_silent`)
      .get();
    expect(item.data()!.body).toContain("Miguel Torres");
    expect(item.data()!.body).toContain(RIZAL);
  });

  it("tells everybody once, however many ways they qualify", async () => {
    // The adviser of the class who is also the guidance counsellor is
    // one person and one notification.
    await db().doc(FirestorePaths.userDoc(SCHOOL, "u_adviser_rizal")).update({role: "guidance"});
    const reached = await raise("alert_dedupe");
    expect(reached.filter((uid) => uid === "u_adviser_rizal")).toHaveLength(1);
  });
});
