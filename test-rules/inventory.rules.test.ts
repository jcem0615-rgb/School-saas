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
 * whether there is chalk before walking down there is the point.
 *
 * Writing is where this used to be wrong. The rules said `allow write`
 * for the three roles that keep the room, which is create, update *and*
 * delete with no field guard -- so any of them could set `quantityOnHand`
 * to whatever they liked with no movement behind it, and could hard-delete
 * an item the log still referred to. Both contradicted comments sitting
 * beside the code: one in these rules calling the quantity a running total
 * maintained alongside its movement, one in the data source saying the
 * rules denied a hard delete. Neither was true, and nothing tested either,
 * which is why it survived.
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
  it("staff edit what an item is", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(updateDoc(doc(db, ITEM), {reorderLevel: 10}));
    await assertSucceeds(updateDoc(doc(db, ITEM), {location: "Stock room B"}));
  });

  it("the admin, who owns what the school buys", async () => {
    const db = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(updateDoc(doc(db, ITEM), {reorderLevel: 8}));
  });

  it("not the director, who reads the stock room and does not keep it", async () => {
    // Supervision, not operation. See the note at the top of
    // firestore.rules.
    const db = contextAs("director", "director_a").firestore();
    await assertFails(updateDoc(doc(db, ITEM), {reorderLevel: 8}));
  });

  it("not a teacher, who reads it every day", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(updateDoc(doc(db, ITEM), {reorderLevel: 1}));
  });

  it("a new item starts at nothing on hand", async () => {
    // Not at whatever the person adding it types. The first delivery is
    // a movement like any other, which is what makes the opening figure
    // traceable rather than asserted.
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/inventory/item_new`), {
        ...item(),
        id: "item_new",
        quantityOnHand: 0,
      })
    );
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/inventory/item_stocked`), {
        ...item(),
        id: "item_stocked",
        quantityOnHand: 40,
      })
    );
  });
});

describe("the count on an item", () => {
  it("cannot be moved by anybody, whatever their role", async () => {
    // The count moves through `recordInventoryMovement`, which writes
    // the movement and the new total in one transaction. A count a
    // console could set is a figure with nothing behind it -- which is
    // the spreadsheet this module replaces.
    for (const [role, uid] of [
      ["director", "director_a"],
      ["admin", "admin_a"],
      ["staff", "staff_a"],
    ]) {
      const db = contextAs(role, uid).firestore();
      await assertFails(updateDoc(doc(db, ITEM), {quantityOnHand: 999}));
      // Not even downwards, and not even by one.
      await assertFails(updateDoc(doc(db, ITEM), {quantityOnHand: 11}));
    }
  });

  it("survives an edit to everything around it", async () => {
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, ITEM), {name: "Bond paper A4", unit: "box", reorderLevel: 2})
    );
  });
});

describe("the movement log", () => {
  it("cannot be written by a client at all", async () => {
    // Server-only. A movement and the total it moved are written
    // together or not at all; one a client could write on its own is a
    // log entry with nothing behind it, and the pair could disagree.
    for (const [role, uid] of [
      ["director", "director_a"],
      ["admin", "admin_a"],
      ["staff", "staff_a"],
      ["student", "student_a"],
    ]) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        setDoc(doc(db, `schools/${SCHOOL}/inventoryTransactions/mv_${uid}`), movement())
      );
    }
  });
});

describe("the movement log, afterwards", () => {
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

  it("keeps the item it refers to, which cannot be hard-deleted", async () => {
    // The data source has always soft-deleted, and said in a comment
    // that the rules denied the other kind. They did not.
    for (const [role, uid] of [
      ["director", "director_a"],
      ["admin", "admin_a"],
      ["staff", "staff_a"],
    ]) {
      const db = contextAs(role, uid).firestore();
      await assertFails(deleteDoc(doc(db, ITEM)));
    }
    // Removing it from the shelves is an update, and that still works.
    const db = contextAs("staff", "staff_a").firestore();
    await assertSucceeds(updateDoc(doc(db, ITEM), {isDeleted: true}));
  });
});
