/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/inventory-emulator"
 *
 * `recordInventoryMovement`, against a real Firestore.
 *
 * The arithmetic is covered pure in test/shared/inventory/. What is
 * tested here is the guarantee the old client-side transaction claimed
 * in a comment and did not implement: that two people reaching for the
 * last projector at the same moment cannot both take it.
 *
 * That one is only testable against a real database. The old code read
 * the item inside its transaction -- the right instinct -- and then
 * checked nothing against what it read; the below-zero test lived on the
 * device, against the copy of the item the screen was holding. Both
 * hands passed it and the shelf went to -2, with nothing on any screen
 * looking wrong.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_stock";
const OTHER_SCHOOL = "school_stock_other";
const ITEM = "item_projector";

/* eslint-disable @typescript-eslint/no-explicit-any */
let callRecordMovement: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

function caller(role: string, uid = `${role}_1`, schoolId: string | undefined = SCHOOL) {
  return {
    uid,
    token: {role, schoolId, status: "active", mustChangePassword: false, name: `${role} one`},
  };
}

const movement = (over: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  itemId: ITEM,
  kind: "issued",
  quantity: 1,
  issuedTo: "Room 204",
  ...over,
});

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.inventory(schoolId),
    FirestorePaths.inventoryTransactions(schoolId),
    FirestorePaths.auditLog(schoolId),
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed(onHand = 5, schoolId = SCHOOL) {
  await db().doc(FirestorePaths.inventoryDoc(schoolId, ITEM)).set({
    id: ITEM,
    schoolId,
    name: "Projector",
    category: "Equipment",
    unit: "piece",
    quantityOnHand: onHand,
    reorderLevel: 1,
    isDeleted: false,
  });
}

async function onHandNow(schoolId = SCHOOL): Promise<number> {
  const snap = await db().doc(FirestorePaths.inventoryDoc(schoolId, ITEM)).get();
  return snap.data()?.quantityOnHand as number;
}

async function movementRows(schoolId = SCHOOL) {
  const snap = await db().collection(FirestorePaths.inventoryTransactions(schoolId)).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()} as Record<string, unknown>));
}

describe("moving stock", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const module = await import("../../../src/callable/inventory/recordInventoryMovement");
    callRecordMovement = fft.wrap(module.recordInventoryMovement);
  });

  afterAll(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    fft.cleanup();
  });

  beforeEach(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    await seed(5);
  });

  describe("who may move it", () => {
    it("is the roles that keep the stock room", async () => {
      for (const role of ["admin", "staff"]) {
        await callRecordMovement({data: movement(), auth: caller(role)} as never);
      }
      expect(await onHandNow()).toBe(3);
    });

    it("is not a teacher, and not the Director, who read the shelf without emptying it", async () => {
      for (const role of ["faculty", "director", "principal"]) {
        await expect(
          callRecordMovement({data: movement(), auth: caller(role)} as never)
        ).rejects.toThrow(/role/i);
      }
      expect(await onHandNow()).toBe(5);
    });

    it("is nobody at all when signed out", async () => {
      await expect(callRecordMovement({data: movement()} as never)).rejects.toThrow(
        /signed in/i
      );
    });

    it("is not somebody from another school", async () => {
      await seed(5, OTHER_SCHOOL);
      await expect(
        callRecordMovement({
          data: movement(),
          auth: caller("staff", "staff_b", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow(/access/i);
      expect(await onHandNow()).toBe(5);
    });
  });

  describe("the movement and the total", () => {
    it("move together, and the log says what it moved between", async () => {
      const result = await callRecordMovement({
        data: movement({kind: "received", quantity: 20, issuedTo: null}),
        auth: caller("staff"),
      } as never);

      expect(result.quantityBefore).toBe(5);
      expect(result.quantityAfter).toBe(25);
      expect(await onHandNow()).toBe(25);

      const rows = await movementRows();
      expect(rows).toHaveLength(1);
      expect(rows[0].quantityBefore).toBe(5);
      expect(rows[0].quantityAfter).toBe(25);
      // Denormalised so the log can be read and replayed without
      // joining back to an item that may since have been renamed.
      expect(rows[0].itemName).toBe("Projector");
      expect(rows[0].recordedBy).toBe("staff_1");
    });

    it("writes neither when the movement is refused", async () => {
      await expect(
        callRecordMovement({data: movement({quantity: 9}), auth: caller("staff")} as never)
      ).rejects.toThrow(/only 5 on hand/i);
      expect(await onHandNow()).toBe(5);
      expect(await movementRows()).toHaveLength(0);
    });

    it("records who is holding it", async () => {
      await callRecordMovement({
        data: movement({quantity: 2, issuedTo: "  Maria Santos  "}),
        auth: caller("staff"),
      } as never);
      const rows = await movementRows();
      expect(rows[0].issuedTo).toBe("Maria Santos");
    });

    it("logs the move for the audit trail", async () => {
      await callRecordMovement({data: movement(), auth: caller("staff")} as never);
      const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
      const entry = snap.docs.map((d) => d.data()).find((d) => d.action === "stock_moved");
      expect(entry).toBeDefined();
      expect((entry!.newValue as {quantityAfter: number}).quantityAfter).toBe(4);
    });
  });

  describe("the count it checks against", () => {
    it("is what is on file, not what the caller sent", async () => {
      // The whole reason this moved off the device. A client cannot
      // name the count it is checked against, nor the resulting total.
      const result = await callRecordMovement({
        data: movement({
          quantity: 2,
          quantityOnHand: 900,
          quantityBefore: 900,
          quantityAfter: 898,
        }),
        auth: caller("staff"),
      } as never);
      expect(result.quantityAfter).toBe(3);
      expect(await onHandNow()).toBe(3);
    });

    it("lets two people take the last two, and refuses the third", async () => {
      await seed(2);
      const results = await Promise.allSettled([
        callRecordMovement({data: movement(), auth: caller("staff", "staff_1")} as never),
        callRecordMovement({data: movement(), auth: caller("staff", "staff_2")} as never),
        callRecordMovement({data: movement(), auth: caller("staff", "staff_3")} as never),
      ]);

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(2);
      expect(await onHandNow()).toBe(0);
      expect(await movementRows()).toHaveLength(2);
    }, 30_000);

    it("never lets the shelf go negative, however many hands reach at once", async () => {
      // The failure this exists to stop, and the one the old comment
      // claimed to have stopped. Nothing errors, both screens look
      // right, and the stock room is short a projector nobody logged.
      await seed(1);
      const results = await Promise.allSettled(
        Array.from({length: 6}, (_, i) =>
          callRecordMovement({data: movement(), auth: caller("staff", `staff_${i}`)} as never)
        )
      );

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      expect(await onHandNow()).toBe(0);
      expect(await movementRows()).toHaveLength(1);
    }, 30_000);
  });

  describe("what it refuses", () => {
    it("a quantity that is not a number", async () => {
      // `double.tryParse('NaN')` returns NaN, and a NaN total is
      // permanent: everything added to it stays NaN.
      for (const bad of [null, "lots", ""]) {
        await expect(
          callRecordMovement({data: movement({quantity: bad}), auth: caller("staff")} as never)
        ).rejects.toThrow(/has to be a number/i);
      }
      expect(await onHandNow()).toBe(5);
    });

    it("an issue with nobody on it", async () => {
      await expect(
        callRecordMovement({
          data: movement({issuedTo: "   "}),
          auth: caller("staff"),
        } as never)
      ).rejects.toThrow(/going to/i);
    });

    it("a kind it has never heard of", async () => {
      await expect(
        callRecordMovement({data: movement({kind: "borrowed"}), auth: caller("staff")} as never)
      ).rejects.toThrow(/kind of movement/i);
    });

    it("an item that is not there, or has been removed", async () => {
      await expect(
        callRecordMovement({
          data: movement({itemId: "item_nothing"}),
          auth: caller("staff"),
        } as never)
      ).rejects.toThrow(/no longer on file/i);

      await db().doc(FirestorePaths.inventoryDoc(SCHOOL, ITEM)).update({isDeleted: true});
      await expect(
        callRecordMovement({data: movement(), auth: caller("staff")} as never)
      ).rejects.toThrow(/no longer on file/i);
    });
  });

  describe("a stock count", () => {
    it("goes either way, because the shelf can disagree either way", async () => {
      await callRecordMovement({
        data: movement({kind: "adjusted", quantity: -2, issuedTo: null}),
        auth: caller("staff"),
      } as never);
      expect(await onHandNow()).toBe(3);

      await callRecordMovement({
        data: movement({kind: "adjusted", quantity: 4, issuedTo: null}),
        auth: caller("staff"),
      } as never);
      expect(await onHandNow()).toBe(7);
    });

    it("still cannot put the shelf below zero", async () => {
      await expect(
        callRecordMovement({
          data: movement({kind: "adjusted", quantity: -9, issuedTo: null}),
          auth: caller("staff"),
        } as never)
      ).rejects.toThrow(/only 5 on hand/i);
    });
  });
});
