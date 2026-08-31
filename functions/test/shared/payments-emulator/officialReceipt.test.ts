/**
 * Requires the Firestore emulator (uses admin.firestore() directly).
 * Run via: firebase emulators:exec --only firestore "jest test/shared/payments-emulator"
 *
 * The BIR receipt series, tested against a real transaction rather than
 * a mock, because what is being tested *is* the transaction: two
 * cashiers typing the same number at the same moment is the case this
 * code exists for, and a stubbed `tx.create` cannot fail the way a real
 * one does.
 */
import * as admin from "firebase-admin";
import {claimOfficialReceipt} from "../../../src/shared/payments/officialReceipt";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const SCHOOL = "school_receipts";

function db() {
  return admin.firestore();
}

/** Runs claimOfficialReceipt inside a transaction, as the caller does. */
async function claim(schoolId: string, typed: number | null, paymentId: string) {
  return db().runTransaction((tx) =>
    claimOfficialReceipt(tx, schoolId, typed, paymentId)
  );
}

async function registerBooklet(
  schoolId: string,
  id: string,
  fields: Record<string, unknown> = {}
) {
  await db()
    .doc(`${FirestorePaths.receiptBooklets(schoolId)}/${id}`)
    .set({
      prefix: "OR-",
      firstNumber: 1,
      lastNumber: 500,
      digits: 4,
      isActive: true,
      isDeleted: false,
      ...fields,
    });
}

async function wipe(schoolId: string) {
  const booklets = await db().collection(FirestorePaths.receiptBooklets(schoolId)).get();
  for (const booklet of booklets.docs) {
    const claims = await booklet.ref.collection("claims").get();
    await Promise.all(claims.docs.map((d) => d.ref.delete()));
    await booklet.ref.delete();
  }
}

describe("claimOfficialReceipt", () => {
  beforeAll(() => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
  });

  afterEach(() => wipe(SCHOOL));

  describe("a school that does not issue official receipts", () => {
    it("takes no number and asks for none", async () => {
      // The ordinary state of every school using this system today, and
      // it has to keep working: recordPayment behaves exactly as it did
      // before any of this existed.
      expect(await claim(SCHOOL, null, "pay_1")).toBeNull();
    });

    it("refuses a number typed against no booklet", async () => {
      // Silently dropping it would lose the one field the cashier
      // cared about.
      await expect(claim(SCHOOL, 42, "pay_1")).rejects.toThrow(
        /No receipt booklet is registered/
      );
    });
  });

  describe("a school with one booklet", () => {
    beforeEach(() => registerBooklet(SCHOOL, "bklt_1"));

    it("claims a number and formats it as it reads on the paper", async () => {
      const claimed = await claim(SCHOOL, 42, "pay_1");
      expect(claimed).not.toBeNull();
      expect(claimed!.number).toBe(42);
      expect(claimed!.formatted).toBe("OR-0042");
      expect(claimed!.bookletId).toBe("bklt_1");
    });

    it("writes the claim at a document id that is the number", async () => {
      // Not a query. That is the uniqueness guarantee, and a query is
      // something two concurrent transactions could both pass.
      await claim(SCHOOL, 42, "pay_1");
      const doc = await db()
        .doc(FirestorePaths.receiptClaimDoc(SCHOOL, "bklt_1", "42"))
        .get();
      expect(doc.exists).toBe(true);
      expect(doc.data()?.paymentId).toBe("pay_1");
    });

    it("requires a number, because this school issues receipts", async () => {
      await expect(claim(SCHOOL, null, "pay_1")).rejects.toThrow(
        /receipt number on the paper is required/
      );
    });

    it("refuses a number outside the registered range, naming the range", async () => {
      await expect(claim(SCHOOL, 900, "pay_1")).rejects.toThrow(
        /OR-0900 is outside the registered booklet \(OR-0001 to OR-0500\)/
      );
    });

    it("refuses the same number twice", async () => {
      await claim(SCHOOL, 42, "pay_1");
      await expect(claim(SCHOOL, 42, "pay_2")).rejects.toThrow(
        /OR-0042 has already been used/
      );
    });

    it("issues one number under concurrent claims, not two", async () => {
      // The case the whole design exists for: two cashiers, one number,
      // the same moment. One wins and the other is told -- rather than
      // both payments filed against one receipt and the discrepancy
      // surfacing at the end of the month.
      const attempts = await Promise.allSettled(
        Array.from({length: 5}, (_, i) => claim(SCHOOL, 77, `pay_${i}`))
      );
      const won = attempts.filter((a) => a.status === "fulfilled");
      expect(won).toHaveLength(1);

      const claims = await db()
        .collection(FirestorePaths.receiptClaims(SCHOOL, "bklt_1"))
        .get();
      expect(claims.size).toBe(1);
    });

    it("keeps the range's own boundaries claimable", async () => {
      expect((await claim(SCHOOL, 1, "pay_1"))!.formatted).toBe("OR-0001");
      expect((await claim(SCHOOL, 500, "pay_2"))!.formatted).toBe("OR-0500");
    });
  });

  it("refuses when two booklets are active at once", async () => {
    // Two cashiers issuing from two ranges with nothing saying which is
    // which. Refusing is safer than picking one.
    await registerBooklet(SCHOOL, "bklt_1");
    await registerBooklet(SCHOOL, "bklt_2", {firstNumber: 501, lastNumber: 1000});

    await expect(claim(SCHOOL, 42, "pay_1")).rejects.toThrow(
      /More than one receipt booklet is marked active/
    );
  });

  it("ignores a soft-deleted booklet, active or not", async () => {
    await registerBooklet(SCHOOL, "bklt_1");
    await registerBooklet(SCHOOL, "bklt_gone", {isDeleted: true});

    expect((await claim(SCHOOL, 42, "pay_1"))!.bookletId).toBe("bklt_1");
  });
});
