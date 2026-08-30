import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc} from "firebase/firestore";

/**
 * The single-device claim.
 *
 * One document per account, `sessions/current`, naming the device that
 * signed in last. Every signed-in device watches its own; a device that
 * reads an id which is not its own signs itself out.
 *
 * What the rules have to guarantee is narrow but absolute: the document
 * belongs to the account holder and to nobody else. Not to a colleague,
 * not to the school's admin, not to the director. Two reasons, and the
 * second is the one that bites:
 *
 *   * where a person is signed in is theirs, not the school's;
 *   * anyone who could *write* it could sign that person out at will,
 *     which turns a sharing deterrent into a way to lock a colleague out
 *     of the app during, say, an enrolment day.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_sessions_test";
const OTHER = "school_sessions_other";

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

function ownerContext(uid: string) {
  return testEnv.authenticatedContext(uid, {role: "owner", status: "active"});
}

const claim = (deviceId: string) => ({
  deviceId,
  deviceLabel: "a web browser",
  claimedAt: new Date("2026-03-01T01:00:00Z"),
});

const sessionPath = (uid: string, schoolId = SCHOOL) =>
  `schools/${schoolId}/users/${uid}/sessions/current`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const id of [SCHOOL, OTHER]) {
      await setDoc(doc(db, `platform_subscriptions/${id}`), {
        schoolId: id,
        currentStatus: "active",
      });
    }
    await setDoc(doc(db, sessionPath("teacher_a")), claim("device_one"));
  });
}

beforeEach(seed);

describe("the account holder", () => {
  it("reads their own claim", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(getDoc(doc(db, sessionPath("teacher_a"))));
  });

  it("claims the account for a new device", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, sessionPath("teacher_a")), claim("device_two"))
    );
  });

  it("claims it for the first time, with no document there yet", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, sessionPath("student_a")), claim("device_one"))
    );
  });

  it("may clear it", async () => {
    // Not something the app does today -- a stale claim is harmless, and
    // the next sign-in overwrites it. Allowed because the alternative is
    // a document a person can create and never be rid of.
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(deleteDoc(doc(db, sessionPath("teacher_a"))));
  });
});

describe("everybody else", () => {
  it("cannot read where a colleague is signed in", async () => {
    for (const [role, uid] of [
      ["faculty", "teacher_b"],
      ["student", "student_a"],
      ["parent", "parent_a"],
      ["registrar", "registrar_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, sessionPath("teacher_a"))));
    }
  });

  it("cannot read it even as the school's admin or director", async () => {
    // These two can edit a teacher's HR fields on the profile document
    // itself. This is not one of those: an admin who could read the
    // claim gains nothing they need, and an admin who could write it
    // could sign a teacher out on demand.
    for (const [role, uid] of [
      ["admin", "admin_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, sessionPath("teacher_a"))));
    }
  });

  it("cannot displace somebody by writing their claim", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      setDoc(doc(db, sessionPath("teacher_a")), claim("attacker_device"))
    );
  });

  it("cannot free somebody's account by deleting their claim", async () => {
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(deleteDoc(doc(db, sessionPath("teacher_a"))));
  });

  it("cannot reach across schools, same uid or not", async () => {
    const db = contextAs("faculty", "teacher_a", OTHER).firestore();
    await assertFails(getDoc(doc(db, sessionPath("teacher_a"))));
    await assertFails(
      setDoc(doc(db, sessionPath("teacher_a")), claim("device_two"))
    );
  });

  it("cannot be read by a signed-out visitor", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, sessionPath("teacher_a"))));
  });
});

describe("the Owner, who belongs to no school", () => {
  const ownerPath = "platform_owner_profiles/owner_a/sessions/current";

  it("claims and reads their own", async () => {
    const db = ownerContext("owner_a").firestore();
    await assertSucceeds(setDoc(doc(db, ownerPath), claim("device_one")));
    await assertSucceeds(getDoc(doc(db, ownerPath)));
  });

  it("cannot reach another owner's", async () => {
    const db = ownerContext("owner_b").firestore();
    await assertFails(getDoc(doc(db, ownerPath)));
    await assertFails(setDoc(doc(db, ownerPath), claim("device_two")));
  });

  it("is not reachable by a school user", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(getDoc(doc(db, ownerPath)));
    await assertFails(setDoc(doc(db, ownerPath), claim("device_two")));
  });

  it("does not open the owner profile document itself to writes", async () => {
    // The parent stays Admin-SDK-only. A subcollection rule does not
    // inherit from its parent, which cuts both ways -- this is the
    // direction that would be a hole.
    const db = ownerContext("owner_a").firestore();
    await assertFails(
      setDoc(doc(db, "platform_owner_profiles/owner_a"), {fullName: "Renamed"})
    );
  });
});
