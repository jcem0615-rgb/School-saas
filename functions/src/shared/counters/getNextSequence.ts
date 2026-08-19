import * as admin from "firebase-admin";
import {FirestorePaths} from "../firestore-paths";

/**
 * Atomically increments and returns the next value of a named per-school
 * counter. Used for human-readable sequential IDs (receipt numbers,
 * student numbers, ...) where naive `collection.length + 1` client logic
 * would race under concurrent writes -- two cashiers issuing receipts at
 * the same moment must never get the same receipt number.
 */
export async function getNextSequence(schoolId: string, counterName: string): Promise<number> {
  const db = admin.firestore();
  const counterRef = db.doc(FirestorePaths.counterDoc(schoolId, counterName));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    const current = (snap.exists ? (snap.data()?.value as number) : 0) ?? 0;
    const next = current + 1;
    tx.set(counterRef, {value: next}, {merge: true});
    return next;
  });
}
