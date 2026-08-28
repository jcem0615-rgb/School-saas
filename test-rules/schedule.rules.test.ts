import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * The timetable is readable by everybody in the school and writable by
 * nobody.
 *
 * Readable, because a timetable is posted on the classroom wall: a
 * student needs their own week, a parent needs to know when their child
 * is in school, a teacher covering a class needs somebody else's slot.
 *
 * Writable by no client at all, because clash detection -- one teacher,
 * one section, one room, one slot -- is the entire feature, and a
 * guarantee that lives only in the UI is not a guarantee. Both writes go
 * through saveScheduleBlock and deleteScheduleBlock.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_schedule_test";

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

function contextAs(role: string, uid = `${role}_1`, schoolId = SCHOOL) {
  return testEnv.authenticatedContext(uid, {
    schoolId,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const block = {
  schoolId: SCHOOL,
  subject: "Mathematics",
  section: "Grade 10 - Rizal",
  teacherId: "faculty_1",
  teacherName: "Maria Santos",
  room: "Room 201",
  dayOfWeek: 1,
  startMinute: 450,
  endMinute: 510,
  schoolYear: "2026-2027",
  isDeleted: false,
};

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    // Written with rules disabled, exactly as the callable's Admin SDK
    // write would land.
    await setDoc(doc(db, `schools/${SCHOOL}/scheduleBlocks/sched_1`), block);
  });
}

beforeEach(seedFixtures);

describe("reading the timetable", () => {
  const readers = ["director", "principal", "admin", "registrar", "faculty", "student", "parent"];
  for (const role of readers) {
    test(`a ${role} can read it`, async () => {
      const context = contextAs(role);
      await assertSucceeds(
        getDoc(doc(context.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`))
      );
    });
  }

  // Tenant isolation still applies: readable by the school, not by the
  // world.
  test("somebody from another school cannot", async () => {
    const outsider = contextAs("admin", "admin_other", "some_other_school");
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`))
    );
  });

  test("a signed-out visitor cannot", async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      getDoc(doc(anon.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`))
    );
  });
});

describe("writing the timetable", () => {
  // The heart of it. If any of these succeeded, a client could book two
  // classes into one room and the clash check would be decoration.
  const writers = ["director", "principal", "admin", "registrar", "faculty"];
  for (const role of writers) {
    test(`a ${role} cannot create a class directly`, async () => {
      const context = contextAs(role);
      await assertFails(
        setDoc(doc(context.firestore(), `schools/${SCHOOL}/scheduleBlocks/new_1`), block)
      );
    });

    test(`a ${role} cannot move one directly`, async () => {
      const context = contextAs(role);
      await assertFails(
        updateDoc(doc(context.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`), {
          startMinute: 600,
          endMinute: 660,
        })
      );
    });
  }

  test("a teacher cannot move their own class out of somebody else's way", async () => {
    const faculty = contextAs("faculty", "faculty_1");
    await assertFails(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`), {
        room: "Room 999",
      })
    );
  });

  test("nobody can delete one", async () => {
    const admin = contextAs("admin");
    await assertFails(
      deleteDoc(doc(admin.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`))
    );
  });

  test("a student cannot invent a free period", async () => {
    const student = contextAs("student");
    await assertFails(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/scheduleBlocks/sched_1`), {
        isDeleted: true,
      })
    );
  });
});
