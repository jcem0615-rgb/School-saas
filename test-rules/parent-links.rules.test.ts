import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc} from "firebase/firestore";

/**
 * Which children a parent account can see.
 *
 * `users/{uid}.linkedStudentIds` is a permission list wearing the clothes
 * of a profile field. Every parent read in firestore.rules -- grades,
 * attendance, the statement of account, guidance summons, emergency
 * alerts, the messaging thread -- resolves to "is this studentId in that
 * array?". Nothing else gates it.
 *
 * The rule that lets a Director or Admin edit a user document is a
 * denylist: everything is writable except the few fields named on it. So
 * until linkedStudentIds was added to that list, either of them could
 * hand one family sight of another family's child -- their marks, their
 * balance, and a private line to their teacher -- with a client write
 * that nothing recorded and nothing on either screen made visible.
 *
 * setParentLink.ts is the only writer now, and it audits.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_parent_links_test";

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

function contextAs(role: string, uid: string) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const parentDoc = `schools/${SCHOOL}/users/parent_a`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, parentDoc), {
      id: "parent_a",
      schoolId: SCHOOL,
      role: "parent",
      firstName: "Rosario",
      lastName: "Torres",
      email: "rosario@example.ph",
      phone: "0917 555 0142",
      status: "active",
      isDeleted: false,
      // Her own child. The one she is supposed to see.
      linkedStudentIds: ["stu_own"],
    });
  });
}

beforeEach(seed);

describe("nobody grants a parent access from the client", () => {
  it("an admin cannot add a child to a parent's list", async () => {
    // The direction that matters: stu_other belongs to a different
    // family. This write used to succeed, silently.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(doc(db, parentDoc), {linkedStudentIds: ["stu_own", "stu_other"]})
    );
  });

  it("a director cannot either, despite being able to edit the rest of the record", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(
      updateDoc(doc(db, parentDoc), {linkedStudentIds: ["stu_own", "stu_other"]})
    );
  });

  it("a registrar cannot, even though they may ask the callable to", async () => {
    // A registrar is exactly who legitimately links parents. They still
    // do not get a direct write: going through setParentLink is what
    // produces the audit line naming who granted the access.
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertFails(
      updateDoc(doc(db, parentDoc), {linkedStudentIds: ["stu_own", "stu_other"]})
    );
  });

  it("the parent cannot grant themselves another child", async () => {
    // The self-edit rule allows only phone, photo and privacy fields, so
    // this was already refused. Asserted anyway: it is the write an
    // attacker with a stolen parent login would try first, and it should
    // stay refused if that field list is ever widened.
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      updateDoc(doc(db, parentDoc), {linkedStudentIds: ["stu_own", "stu_other"]})
    );
  });

  it("cannot be smuggled in alongside an edit that is otherwise allowed", async () => {
    // An admin editing a phone number in the same write. The rule reads
    // affectedKeys, so the legitimate half does not carry the other one
    // through.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(
      updateDoc(doc(db, parentDoc), {
        phone: "0917 555 0199",
        linkedStudentIds: ["stu_own", "stu_other"],
      })
    );
  });

  it("cannot be emptied from the client either", async () => {
    // Removing access is quieter than granting it and just as much a
    // change: a parent who stops seeing their child rings the office and
    // nobody can say what happened.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(updateDoc(doc(db, parentDoc), {linkedStudentIds: []}));
  });
});

describe("the rest of the record still works", () => {
  it("an admin may still edit the fields they are meant to", async () => {
    // The check has to be narrow. An admin who could no longer correct a
    // parent's phone number would just be a different bug.
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, parentDoc), {phone: "0917 555 0199", firstName: "Rosario A."})
    );
  });

  it("a parent may still edit their own phone number", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(updateDoc(doc(db, parentDoc), {phone: "0918 555 0100"}));
  });

  it("a write that leaves the field exactly as it was is not blocked", async () => {
    // affectedKeys is a diff, not a presence check. Worth pinning: a
    // client that sends the whole document back unchanged -- which is
    // what a naive form save does -- must not be refused for a field it
    // did not actually alter.
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, parentDoc), {
        linkedStudentIds: ["stu_own"],
        firstName: "Rosario",
        phone: "0917 555 0142",
      })
    );
  });
});
