/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/announcements-emulator"
 *
 * Who a new announcement actually reaches.
 *
 * The defect pinned here was silent and total. Teachers were given a way
 * to post to one of their classes; the client learned about `sections`
 * and the notification side did not, so this trigger read every class
 * notice as "addressed to nobody" and returned before writing a single
 * inbox item. The notice appeared in the app's list, where a parent
 * would find it only by going to look -- which is not what anybody means
 * by telling a class that tomorrow's trip is cancelled.
 *
 * These assert on the inbox, not on the push. The inbox is the
 * dependable half: it survives a phone that was off and a token that
 * went stale, and it is the half a test can hold still.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_announce";
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

/** Every uid that got an inbox item for this announcement. */
async function notified(announcementId: string): Promise<string[]> {
  const itemId = `announcement_${announcementId}`;
  const snap = await db().collectionGroup("items").get();
  return snap.docs
    .filter((d) => d.id === itemId && d.ref.path.startsWith(`schools/${SCHOOL}/`))
    // .../notifications/{uid}/items/{itemId}
    .map((d) => d.ref.path.split("/")[3])
    .sort();
}

/** Writes the announcement and runs the trigger over it. */
async function post(
  id: string,
  audience: Record<string, unknown> | undefined,
  extra: Record<string, unknown> = {}
): Promise<string[]> {
  const data = {
    id,
    schoolId: SCHOOL,
    title: "Field trip",
    body: "Bring the signed permit slip tomorrow.",
    ...(audience === undefined ? {} : {audience}),
    isDeleted: false,
    ...extra,
  };
  const path = `schools/${SCHOOL}/announcements/${id}`;
  await db().doc(path).set(data);
  await fanOut({
    data: fft.firestore.makeDocumentSnapshot(data, path),
    params: {schoolId: SCHOOL, announcementId: id},
  } as never);
  return notified(id);
}

async function seed() {
  for (const path of [
    FirestorePaths.users(SCHOOL),
    FirestorePaths.students(SCHOOL),
    FirestorePaths.teacherAssignments(SCHOOL),
    `schools/${SCHOOL}/announcements`,
  ]) {
    await clear(path);
  }
  // Inbox items live under notifications/{uid}/items, which a collection
  // delete does not reach.
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
    user("u_student_mabini", "student"),
    user("u_parent_rizal", "parent", {linkedStudentIds: ["stu_rizal"]}),
    user("u_parent_mabini", "parent", {linkedStudentIds: ["stu_mabini"]}),
    user("u_teacher_rizal", "faculty"),
    user("u_teacher_mabini", "faculty"),
    user("u_admin", "admin"),
    // Left the school. Still on the roll of the class, and must not be
    // notified -- an account that cannot sign in has no inbox to read.
    user("u_student_gone", "student", {status: "inactive"}),
  ]);

  await Promise.all([
    db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_rizal")).set({
      id: "stu_rizal",
      userId: "u_student_rizal",
      section: RIZAL,
      status: "enrolled",
      isDeleted: false,
    }),
    db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_mabini")).set({
      id: "stu_mabini",
      userId: "u_student_mabini",
      section: MABINI,
      status: "enrolled",
      isDeleted: false,
    }),
    db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_gone")).set({
      id: "stu_gone",
      userId: "u_student_gone",
      section: RIZAL,
      status: "transferred",
      isDeleted: false,
    }),
  ]);

  await Promise.all([
    // Typed differently from the student record on purpose. This is what
    // a school's data actually looks like, and matching it exactly is
    // how a teacher's own class notice misses their own class.
    db().collection(FirestorePaths.teacherAssignments(SCHOOL)).doc("ta_1").set({
      teacherId: "u_teacher_rizal",
      teacherName: "Maria Santos",
      section: "  grade 10  -  rizal ",
      subject: "Mathematics",
    }),
    db().collection(FirestorePaths.teacherAssignments(SCHOOL)).doc("ta_2").set({
      teacherId: "u_teacher_mabini",
      teacherName: "Dennis Pascual",
      section: MABINI,
      subject: "Science",
    }),
  ]);
}

describe("who a new announcement reaches", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const mod = await import("../../../src/triggers/announcements/onAnnouncementCreated");
    fanOut = fft.wrap(mod.onAnnouncementCreated);
  });

  afterAll(() => {
    fft.cleanup();
  });

  beforeEach(seed);

  describe("a teacher posting to one class", () => {
    it("reaches the class, their families and the teachers who take them", async () => {
      // The defect. This used to notify nobody at all.
      const reached = await post("ann_class", {all: false, roles: [], sections: [RIZAL]});
      expect(reached).toEqual(["u_parent_rizal", "u_student_rizal", "u_teacher_rizal"]);
    });

    it("reaches the teacher even though the section is spelt differently on their assignment", async () => {
      const reached = await post("ann_typed", {all: false, roles: [], sections: ["GRADE 10 - RIZAL"]});
      expect(reached).toContain("u_teacher_rizal");
      expect(reached).toContain("u_student_rizal");
    });

    it("reaches nobody in another class, and no one who is in no class", async () => {
      const reached = await post("ann_other", {all: false, roles: [], sections: [RIZAL]});
      expect(reached).not.toContain("u_student_mabini");
      expect(reached).not.toContain("u_parent_mabini");
      expect(reached).not.toContain("u_teacher_mabini");
      expect(reached).not.toContain("u_admin");
    });

    it("does not notify an account that has left the school", async () => {
      const reached = await post("ann_gone", {all: false, roles: [], sections: [RIZAL]});
      expect(reached).not.toContain("u_student_gone");
    });
  });

  describe("the notices that already worked", () => {
    it("a school-wide notice still reaches every active account", async () => {
      const reached = await post("ann_all", {all: true, roles: []});
      expect(reached).toHaveLength(7);
      expect(reached).not.toContain("u_student_gone");
    });

    it("a staff notice still reaches no student or parent", async () => {
      const reached = await post("ann_staff", {
        all: false,
        roles: ["director", "principal", "admin", "registrar", "faculty", "staff", "guidance"],
      });
      expect(reached).toEqual(["u_admin", "u_teacher_mabini", "u_teacher_rizal"]);
    });

    it("a notice addressed to nobody notifies nobody", async () => {
      expect(await post("ann_none", {all: false, roles: [], sections: []})).toEqual([]);
    });

    it("a notice with no audience field at all notifies nobody", async () => {
      // Fails closed. A push cannot be unsent.
      expect(await post("ann_missing", undefined)).toEqual([]);
    });

    it("a deleted announcement notifies nobody", async () => {
      expect(await post("ann_deleted", {all: true, roles: []}, {isDeleted: true})).toEqual([]);
    });
  });
});
