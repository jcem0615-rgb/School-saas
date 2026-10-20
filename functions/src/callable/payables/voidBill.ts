import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {STANDARD_CHART} from "../../shared/ledger/accounts";
import {
  ensureChartOfAccounts,
  postJournalEntryInTransaction,
} from "../../shared/ledger/postJournalEntry";
import {BillLineInput, voidBillJournalLines} from "../../shared/ledger/billLines";

interface VoidBillData {
  schoolId: string;
  billId: string;
  reason: string;
}

const PAYABLES_ROLES = ["director", "admin"];

/**
 * Voids a bill that should never have been recorded.
 *
 * A duplicate of an invoice already entered, a bill for the wrong
 * school. Not a deletion: the bill stays, marked void with a reason, and
 * the liability is reversed by its own entry -- the same argument as
 * everywhere else in this system, that a correction is itself part of
 * the record.
 *
 * Only a bill with nothing paid against it can be voided. Once money has
 * gone out the cash really did leave, and pretending the bill never
 * existed would leave a payment pointing at nothing. A part-paid bill
 * that turns out to be wrong is settled or credited, not vanished.
 */
export const voidBill = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<VoidBillData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, billId, reason} = request.data ?? {};

    if (!schoolId || !billId || !reason) {
      throw new HttpsError("invalid-argument", "Missing bill or reason.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!PAYABLES_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the Director or an Admin can void a bill."
      );
    }
    const why = reason.trim();
    if (why.length < 4) {
      throw new HttpsError("invalid-argument", "Say why it is being voided.");
    }

    const db = admin.firestore();
    const billRef = db.doc(FirestorePaths.billDoc(schoolId, billId));
    const first = await billRef.get();
    if (!first.exists) {
      throw new HttpsError("not-found", "That bill is not on the list.");
    }

    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const journalSequence = await getNextSequence(schoolId, "journalEntryNumber");
    const byName = (request.auth!.token.name as string) ?? "Unknown";

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(billRef);
      const bill = fresh.data();
      if (!bill) {
        throw new HttpsError("not-found", "That bill is not on the list.");
      }
      if (bill.voidedAt) {
        throw new HttpsError("failed-precondition", "That bill is already void.");
      }
      if (((bill.amountPaid as number) ?? 0) > 0) {
        throw new HttpsError(
          "failed-precondition",
          "Money has already been paid against this bill, so it cannot be " +
            "voided. Record a credit from the supplier instead."
        );
      }

      postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          // Dated today. A reversal filed into a period somebody has
          // already reported on quietly changes last month's figures.
          date: new Date(),
          memo: `Void ${bill.vendorName} invoice ${bill.billNumber}: ${why}`,
          source: "reversal",
          sourceId: billId,
          reversalOf: (bill.journalEntryId as string) ?? null,
          postedBy: request.auth!.uid,
          postedByName: byName,
          lines: voidBillJournalLines(bill.lines as BillLineInput[]),
        },
        journalSequence
      );

      tx.update(billRef, {
        status: "void",
        voidedAt: admin.firestore.FieldValue.serverTimestamp(),
        voidedBy: request.auth!.uid,
        voidedByName: byName,
        voidReason: why,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: byName,
      module: "payables",
      action: "bill_voided",
      targetCollection: FirestorePaths.bills(schoolId),
      targetId: billId,
      newValue: {reason: why},
      success: true,
    });

    return {billId};
  }
);
