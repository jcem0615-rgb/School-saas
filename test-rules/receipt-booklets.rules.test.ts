import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, updateDoc} from "firebase/firestore";

/**
 * The BIR official-receipt series.
 *
 * Two things have to hold. A booklet's range is a statement about a
 * government permit, so only Director/Admin may register one -- a
 * cashier who could widen the range could issue receipts outside it and
 * the reconciliation would never notice.
 *
 * And the claim documents, whose ids *are* the receipt numbers, are
 * server-written only. A client that could create one could reserve a
 * number with no payment behind it; one that could delete one could free
 * a number already handed to a family, which is the same serial on two
 * different receipts.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_receipts_test";

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

const booklet = (overrides: Record<string, unknown> = {}) => ({
  prefix: "OR-",
  firstNumber: 1,
  lastNumber: 500,
  digits: 4,
  atpNumber: "OCN 3AU0000123456",
  isActive: true,
  isDeleted: false,
  ...overrides,
});

const BOOKLET = `schools/${SCHOOL}/receiptBooklets/bklt_001`;
const CLAIM = `${BOOKLET}/claims/42`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, BOOKLET), booklet());
    await setDoc(doc(db, CLAIM), {
      number: 42,
      formatted: "OR-0042",
      paymentId: "pay_1",
      cancelled: false,
    });
  });
}

beforeEach(seed);

describe("who may register a booklet", () => {
  it("a director may", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/receiptBooklets/bklt_002`), booklet())
    );
  });

  it("an admin may", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/receiptBooklets/bklt_003`), booklet())
    );
  });

  it("a registrar may not, though they read it every day", async () => {
    // The cashier needs to know which booklet is in use. Letting them
    // widen its range would let them issue receipts outside it, and the
    // reconciliation would report nothing wrong.
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertSucceeds(getDoc(doc(db, BOOKLET)));
    await assertFails(
      updateDoc(doc(db, BOOKLET), {lastNumber: 100000})
    );
  });

  it("faculty cannot even read it", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(getDoc(doc(db, BOOKLET)));
  });

  it("a parent cannot read it", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(getDoc(doc(db, BOOKLET)));
  });

  it("nobody may delete one", async () => {
    // Closed by setting isActive. Every payment citing one of its
    // numbers has to stay explainable to an examiner.
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertFails(deleteDoc(doc(db, BOOKLET)));
    }
  });

  it("another school cannot reach it", async () => {
    const db = contextAs("director", "director_a", "some_other_school").firestore();
    await assertFails(getDoc(doc(db, BOOKLET)));
    await assertFails(updateDoc(doc(db, BOOKLET), {lastNumber: 999}));
  });
});

describe("the claim on a receipt number", () => {
  it("is readable by whoever handles money", async () => {
    for (const role of ["director", "admin", "registrar"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, CLAIM)));
    }
  });

  it("cannot be created by a client, not even the director", async () => {
    // A reserved number with no payment behind it is a hole in the
    // series that looks like a legitimate use.
    const db = contextAs("director", "director_a").firestore();
    await assertFails(
      setDoc(doc(db, `${BOOKLET}/claims/43`), {number: 43, paymentId: "made_up"})
    );
  });

  it("cannot be deleted by a client", async () => {
    // Freeing a number already handed to a family is the same serial on
    // two different receipts.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(deleteDoc(doc(db, CLAIM)));
  });

  it("cannot be edited to point at another payment", async () => {
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertFails(updateDoc(doc(db, CLAIM), {paymentId: "pay_other"}));
  });
});
