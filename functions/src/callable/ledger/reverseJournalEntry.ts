import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {postJournalEntryInTransaction} from "../../shared/ledger/postJournalEntry";

interface ReverseEntryData {
  schoolId: string;
  entryId: string;
  reason: string;
}

const LEDGER_ROLES = ["director", "admin"];

/**
 * Posts the reverse of an entry.
 *
 * The only correction there is. Every debit becomes a credit and back
 * again, and both the mistake and the fix stay on the record -- which is
 * what an accounting office does with a paper journal, and for the same
 * reason: a book you can go back and tidy is a book nobody can rely on.
 *
 * `reversedBy` goes onto the original in the same transaction. It is the
 * only field on a journal entry that ever changes, and it is written
 * here rather than from a client -- firestore.rules refuses every client
 * write to the journal.
 */
export const reverseJournalEntry = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<ReverseEntryData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, entryId, reason} = request.data ?? {};

    if (!schoolId || !entryId || !reason) {
      throw new HttpsError("invalid-argument", "Missing entry or reason.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!LEDGER_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the Director or an Admin can reverse an entry."
      );
    }
    const why = reason.trim();
    if (why.length < 4) {
      throw new HttpsError("invalid-argument", "Say why it is being reversed.");
    }

    const db = admin.firestore();
    const originalRef = db.doc(FirestorePaths.journalEntryDoc(schoolId, entryId));
    const snap = await originalRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "That entry is not in the journal.");
    }
    const original = snap.data()!;

    if (original.reversedBy) {
      throw new HttpsError(
        "failed-precondition",
        `Entry ${original.entryNumber} has already been reversed.`
      );
    }
    if (original.reversalOf) {
      // Reversing a reversal is how a journal turns into a tangle nobody
      // can read. If the reversal was wrong, post the original again.
      throw new HttpsError(
        "failed-precondition",
        `Entry ${original.entryNumber} is itself a reversal. Post a fresh ` +
          "entry instead of reversing it."
      );
    }

    const lines = (original.lines as {
      accountCode: string;
      accountName: string;
      debit: number;
      credit: number;
      memo: string | null;
    }[]).map((l) => ({
      accountCode: l.accountCode,
      accountName: l.accountName,
      // Swapped, which is the whole of a reversal.
      debit: l.credit,
      credit: l.debit,
      memo: l.memo ?? undefined,
    }));

    const sequence = await getNextSequence(schoolId, "journalEntryNumber");
    let posted!: {id: string; entryNumber: string};

    await db.runTransaction(async (tx) => {
      // Re-read inside the transaction: two people reversing the same
      // entry at once would otherwise both pass the check above and post
      // two reversals, which doubles the correction.
      const fresh = await tx.get(originalRef);
      if (fresh.data()?.reversedBy) {
        throw new HttpsError(
          "failed-precondition",
          "That entry was reversed while this was being prepared."
        );
      }

      posted = postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          // Dated today, not back-dated to the original. The correction
          // happened today, and a reversal filed into a closed period is
          // how last month's reported figures quietly change.
          date: new Date(),
          memo: `Reversal of ${original.entryNumber}: ${why}`,
          source: "reversal",
          sourceId: entryId,
          reversalOf: entryId,
          postedBy: request.auth!.uid,
          postedByName: (request.auth!.token.name as string) ?? "Unknown",
          lines,
        },
        sequence
      );

      tx.update(originalRef, {
        reversedBy: posted.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "ledger",
      action: "journal_entry_reversed",
      targetCollection: FirestorePaths.journalEntries(schoolId),
      targetId: entryId,
      newValue: {reversalId: posted.id, entryNumber: posted.entryNumber, reason: why},
      success: true,
    });

    return posted;
  }
);
