import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {FirestorePaths} from "../firestore-paths";

/** A booklet as it is stored. */
interface BookletDoc {
  prefix?: string;
  firstNumber?: number;
  lastNumber?: number;
  digits?: number;
  isActive?: boolean;
  isDeleted?: boolean;
}

export interface ClaimedReceipt {
  /** The number, as an integer. */
  number: number;
  /** How it reads on the paper, e.g. "OR-0042". */
  formatted: string;
  bookletId: string;
}

/**
 * Reserves an official receipt number, or refuses.
 *
 * Called inside the payment transaction, so a number and the payment that
 * cites it are written together or neither is. Two cashiers typing the
 * same number at the same moment is the case this exists for: the claim
 * document's id *is* the number, so the second `create` fails and the
 * second cashier is told, rather than both payments being filed against
 * one receipt and the discrepancy surfacing at the end of the month.
 *
 * Returns null when the school does not issue official receipts. That is
 * the ordinary state of every school using this system today, and it must
 * keep working: no booklet registered means no number required, and
 * `recordPayment` behaves exactly as it did before this existed.
 */
export async function claimOfficialReceipt(
  tx: admin.firestore.Transaction,
  schoolId: string,
  typedNumber: number | undefined | null,
  paymentId: string
): Promise<ClaimedReceipt | null> {
  const db = admin.firestore();

  const bookletsSnap = await tx.get(
    db
      .collection(FirestorePaths.receiptBooklets(schoolId))
      .where("isActive", "==", true)
      .limit(2)
  );

  const active = bookletsSnap.docs.filter((d) => (d.data() as BookletDoc).isDeleted !== true);

  if (active.length === 0) {
    // No booklet. If a number was typed anyway, that is a cashier
    // recording something the school has not told the system about, and
    // silently dropping it would lose the one field they cared about.
    if (typedNumber !== undefined && typedNumber !== null) {
      throw new HttpsError(
        "failed-precondition",
        "No receipt booklet is registered, so there is nothing to check " +
          "this number against. Register the booklet first."
      );
    }
    return null;
  }
  if (active.length > 1) {
    // Two active booklets means two cashiers issuing from two ranges with
    // nothing saying which is which. Refusing is safer than picking one.
    throw new HttpsError(
      "failed-precondition",
      "More than one receipt booklet is marked active. Close the one that " +
        "is finished before recording more payments."
    );
  }

  const doc = active[0];
  const booklet = doc.data() as BookletDoc;
  const first = Number(booklet.firstNumber);
  const last = Number(booklet.lastNumber);
  const digits = Math.min(Math.max(Number(booklet.digits) || 4, 1), 12);
  const prefix = booklet.prefix ?? "";

  if (typedNumber === undefined || typedNumber === null) {
    throw new HttpsError(
      "invalid-argument",
      "This school issues official receipts, so the receipt number on the " +
        "paper is required."
    );
  }

  const number = Math.trunc(Number(typedNumber));
  if (!Number.isFinite(number)) {
    throw new HttpsError("invalid-argument", "That receipt number is not a number.");
  }
  const formatted = `${prefix}${String(number).padStart(digits, "0")}`;

  if (!Number.isFinite(first) || !Number.isFinite(last) || number < first || number > last) {
    throw new HttpsError(
      "invalid-argument",
      `${formatted} is outside the registered booklet ` +
        `(${prefix}${String(first).padStart(digits, "0")} to ` +
        `${prefix}${String(last).padStart(digits, "0")}).`
    );
  }

  // The number is the document id. That is the uniqueness guarantee --
  // not a query, which two concurrent transactions could both pass.
  const claimRef = db.doc(FirestorePaths.receiptClaimDoc(schoolId, doc.id, String(number)));
  const existing = await tx.get(claimRef);
  if (existing.exists) {
    const holder = existing.data() ?? {};
    throw new HttpsError(
      "already-exists",
      `${formatted} has already been used${
        holder.cancelled === true ? " and cancelled" : ""
      }. Every official receipt number is issued once.`
    );
  }

  tx.create(claimRef, {
    number,
    formatted,
    bookletId: doc.id,
    paymentId,
    cancelled: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {number, formatted, bookletId: doc.id};
}
