import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, updateDoc} from "firebase/firestore";

/**
 * The stock room.
 *
 * Readable by everybody in the school, because a teacher wanting to know
 * whether there is chalk before walking down there is the point. The
 * movement log is append-only: the quantity on an item is a running
 * total kept alongside the movement that changed it, so a log that could
 * be edited afterwards leaves a figure nobody can trace.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_inventory_test";
const ITEM = `schools/${SCHOOL}/inventory/item_1`;
const MOVEMENT = `schools/${SCHOOL}/inventoryTransactions/mv_1`;

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

const item = () => ({
  id: "item_1",
  name: "Bond paper",
  category: "Office supplies",
  unit: "ream",
  quantityOnHand: 12,
  reorderLevel: 5,
  isDeleted: false,
});

const movement = () => ({
  itemId: "item_1",
  itemName: "Bond paper",
  kind: "issued",
  quantity: 2,
  issuedTo: "Maria Santos",
  recordedByName: "Ricardo Aquino",
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, ITEM), item());
    await setDoc(doc(db, MOVEMENT), movement());
  });
}

beforeEach(seed);

describe("who may look", () => {
  it("anybody in the school, including a teacher", async () => {
    // Knowing whether there is chalk before walking down there is the
    // point, and there is nothing sensitive in forty reams of paper.
    for (const role of ["faculty", "staff", "registrar", "guidance", "student"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, ITEM)));
      await assertSucceeds(getDoc(doc(db, MOVEMENT)));
    }
  });

  it("but not somebody from another school", async () => {
    const db = contextAs("staff", "staff_b", "another_school").firestore();
    await assertFails(getDoc(doc(db, ITEM)));
  });
});

describe("who may keep it", () => {
  it("staff, who run the stock room", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(updateDoc(doc(db, ITEM), {reorderLevel: 10}));
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/inventoryTransactions/mv_2`), movement())
    );
  });

  it("director and admin, who own what the school buys", async () => {
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(updateDoc(doc(db, ITEM), {reorderLevel: 8}));
    }
  });

  it("not a teacher, who reads it every day", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(updateDoc(doc(db, ITEM), {quantityOnHand: 999}));
  });

  it("not a student", async () => {
    const db = contextAs("student", "student_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/inventoryTransactions/mv_3`), movement())
    );
  });
});

describe("the movement log", () => {
  it("cannot be edited after the fact", async () => {
    // The item's quantity is a running total kept alongside these. A log
    // that could be rewritten leaves a figure nobody can trace.
    const db = contextAs("staff", "staff_a").firestore();
    await assertFails(updateDoc(doc(db, MOVEMENT), {quantity: 99}));
  });

  it("cannot be deleted, even by a director", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(deleteDoc(doc(db, MOVEMENT)));
  });
});
