import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, getDocs, collection} from "firebase/firestore";

/**
 * Push notification device tokens.
 *
 * One document per device, keyed BY the token, under the account it
 * belongs to. A subcollection rather than a field on the user document,
 * because users/{userId} is readable by everyone in the school -- and a
 * token is not an identifier, it is a capability: anyone holding one can
 * push a notification to that device.
 *
 * So the rule has to hold two lines at once, and the second is the one
 * that bites:
 *
 *   * nobody may READ a colleague's token, or they can push to that
 *     person's phone in the school's name -- a fake emergency alert, a
 *     fake summons, from a device the family trusts;
 *   * nobody may WRITE one under another account's id, or they redirect
 *     that person's notifications to their own handset, and the person
 *     who stops being told about the emergency never finds out why.
 *
 * The fan-out in onAnnouncementCreated.ts reads every token in the school
 * through the Admin SDK, which bypasses rules entirely. Nothing here
 * needs to open a door for it, and this file exists to prove nothing did.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_device_tokens_test";
const OTHER = "school_device_tokens_other";

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

const TOKEN_A = "fcm_token_teacher_a_phone";
const TOKEN_B = "fcm_token_teacher_b_phone";

const registration = (label: string) => ({
  platform: "android",
  deviceLabel: label,
  registeredAt: new Date("2026-03-01T01:00:00Z"),
});

const tokenPath = (uid: string, token: string, schoolId = SCHOOL) =>
  `schools/${schoolId}/users/${uid}/deviceTokens/${token}`;

const tokensOf = (uid: string, schoolId = SCHOOL) =>
  `schools/${schoolId}/users/${uid}/deviceTokens`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const id of [SCHOOL, OTHER]) {
      await setDoc(doc(db, `platform_subscriptions/${id}`), {
        schoolId: id,
        currentStatus: "active",
      });
    }
    await setDoc(doc(db, tokenPath("teacher_a", TOKEN_A)), registration("a phone"));
    await setDoc(doc(db, tokenPath("teacher_b", TOKEN_B)), registration("a phone"));
  });
}

beforeEach(seed);

describe("the account holder", () => {
  it("registers a token for this device", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_a_new_browser")), registration("a browser"))
    );
  });

  it("re-registers the same token without accumulating a second document", async () => {
    // The document is keyed by the token, so registering the same browser
    // twice is an overwrite. That only works if the holder may write over
    // their own existing document, not merely create a missing one.
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, tokenPath("teacher_a", TOKEN_A)), registration("a phone, again"))
    );
  });

  it("reads and lists their own", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    await assertSucceeds(getDocs(collection(db, tokensOf("teacher_a"))));
  });

  it("removes one when the switch is turned off", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(deleteDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
  });

  it("holds for every role, not only faculty", async () => {
    for (const [role, uid] of [
      ["student", "student_a"],
      ["parent", "parent_a"],
      ["staff", "staff_a"],
      ["guidance", "guidance_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(
        setDoc(doc(db, tokenPath(uid, `fcm_${uid}`)), registration("a phone"))
      );
      await assertSucceeds(getDoc(doc(db, tokenPath(uid, `fcm_${uid}`))));
    }
  });
});

describe("everybody else", () => {
  it("cannot read a colleague's token", async () => {
    for (const [role, uid] of [
      ["faculty", "teacher_b"],
      ["student", "student_a"],
      ["parent", "parent_a"],
      ["registrar", "registrar_a"],
      ["guidance", "guidance_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    }
  });

  it("cannot read one even as the school's admin, principal or director", async () => {
    // These three can read and in places edit a teacher's profile. A
    // token is not profile data: holding it is the ability to push a
    // notification to that person's phone in the school's name.
    for (const [role, uid] of [
      ["admin", "admin_a"],
      ["principal", "principal_a"],
      ["director", "director_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
      await assertFails(getDocs(collection(db, tokensOf("teacher_a"))));
    }
  });

  it("cannot list the school's tokens by walking one account", async () => {
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(getDocs(collection(db, tokensOf("teacher_a"))));
  });

  it("cannot redirect somebody's notifications by writing a token under their id", async () => {
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_attacker_handset")), registration("mine"))
    );
  });

  it("cannot silence somebody by deleting their token", async () => {
    // The direction that costs a person an emergency alert without ever
    // telling them the alert existed.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(deleteDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
  });

  it("cannot reach across schools, same uid or not", async () => {
    const db = contextAs("faculty", "teacher_a", OTHER).firestore();
    await assertFails(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    await assertFails(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_other_school")), registration("elsewhere"))
    );
  });

  it("cannot be reached by a signed-out visitor", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    await assertFails(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_anon")), registration("nobody"))
    );
  });
});

describe("a suspended school", () => {
  it("still lets a person manage their own tokens", async () => {
    // Deliberate, and worth pinning down because it reads like an
    // oversight: this rule checks belongsToSchool() but NOT
    // schoolIsAccessible(), so it sits outside the subscription gate that
    // almost every other path in this file is behind. The sibling
    // sessions/{sessionId} rule does the same thing for the same reason.
    //
    // These two subcollections are account plumbing rather than school
    // data. A person whose school has stopped paying must still be able
    // to sign a device out and turn its notifications off -- locking them
    // out of that would strand a token registered to a phone they no
    // longer want the school reaching.
    //
    // Nothing leaks by allowing it. The token stays readable only by its
    // holder, and the fan-out that would actually send anything runs
    // through the Admin SDK against a school the app has already locked
    // out at a higher level.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
        schoolId: SCHOOL,
        currentStatus: "suspended",
      });
    });
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(deleteDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    await assertSucceeds(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_while_suspended")), registration("a phone"))
    );
  });

  it("does not open a colleague's tokens while suspended either", async () => {
    // The gate that matters is the uid check, and it is not conditional
    // on the subscription. Worth an assertion: a suspended school is
    // exactly when somebody might expect the rules to have gone slack.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
        schoolId: SCHOOL,
        currentStatus: "suspended",
      });
    });
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(getDoc(doc(db, tokenPath("teacher_a", TOKEN_A))));
    await assertFails(
      setDoc(doc(db, tokenPath("teacher_a", "fcm_attacker")), registration("mine"))
    );
  });
});
