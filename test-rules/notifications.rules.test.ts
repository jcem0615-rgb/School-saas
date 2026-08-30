import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc, serverTimestamp} from "firebase/firestore";

/**
 * The notification inbox.
 *
 * Every notification the school sends lands in one of these, keyed by
 * the recipient's uid *in the path* -- which is the point. There is no
 * query anyone can write that reaches somebody else's, because the uid
 * is not a field to be filtered on but part of the address.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_notifications_test";
const LAPSED = "school_notifications_lapsed";

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

const item = (overrides: Record<string, unknown> = {}) => ({
  id: "summons_sum_1",
  kind: "summons",
  title: "Guidance office appointment",
  body: "Ana Cruz is asked to come to the guidance office on Tue 3 Mar.",
  link: "/notifications",
  sourceId: "sum_1",
  data: {},
  isRead: false,
  readAt: null,
  createdAt: new Date("2026-03-01T01:00:00Z"),
  ...overrides,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `platform_subscriptions/${LAPSED}`), {
      schoolId: LAPSED,
      currentStatus: "suspended",
    });
    // Delivered by the Admin SDK, which is the only thing that ever
    // writes one of these.
    await setDoc(
      doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`),
      item()
    );
    await setDoc(
      doc(db, `schools/${LAPSED}/notifications/parent_a/items/summons_sum_1`),
      item()
    );
  });
}

beforeEach(seed);

describe("reading", () => {
  it("a parent reads their own inbox", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(
      getDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`))
    );
  });

  it("nobody reads somebody else's -- not even an admin", async () => {
    // Deliberate. A notification is a message addressed to one person,
    // and the school's own record of what was sent lives in the source
    // document (the summons, the announcement), not in the copy that was
    // delivered to a family's phone.
    for (const [role, uid] of [
      ["parent", "parent_b"],
      ["faculty", "teacher_a"],
      ["admin", "admin_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        getDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`))
      );
    }
  });

  it("a user of another school cannot reach in", async () => {
    const db = contextAs("parent", "parent_a", "some_other_school").firestore();
    await assertFails(
      getDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`))
    );
  });

  it("a suspended school's inbox is closed like everything else", async () => {
    const db = contextAs("parent", "parent_a", LAPSED).firestore();
    await assertFails(
      getDoc(doc(db, `schools/${LAPSED}/notifications/parent_a/items/summons_sum_1`))
    );
  });
});

describe("marking as read", () => {
  it("the recipient may mark their own read", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`), {
        isRead: true,
        readAt: serverTimestamp(),
      })
    );
  });

  it("and may mark it unread again", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`), {
        isRead: false,
        readAt: null,
      })
    );
  });

  it("but may not rewrite what it says", async () => {
    // The one that matters. Without the affectedKeys check, "mark as
    // read" is also "edit the summons you were sent to say a different
    // date", and the family's own record of being told stops being
    // evidence of anything.
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`), {
        body: "Never mind, do not come.",
      })
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`), {
        isRead: true,
        title: "Something else entirely",
      })
    );
  });

  it("nobody else may mark it read", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`), {
        isRead: true,
      })
    );
  });
});

describe("creating and deleting", () => {
  it("no client may post into an inbox", async () => {
    // Including their own: a notification that a user could write is a
    // notification that looks like it came from the school and did not.
    for (const [role, uid] of [
      ["parent", "parent_a"],
      ["guidance", "guidance_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        setDoc(doc(db, `schools/${SCHOOL}/notifications/${uid}/items/forged_1`), item())
      );
    }
  });

  it("the recipient cannot delete the record that they were told", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      deleteDoc(doc(db, `schools/${SCHOOL}/notifications/parent_a/items/summons_sum_1`))
    );
  });
});
