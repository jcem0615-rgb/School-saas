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
  sameMoney,
} from "../../shared/ledger/postJournalEntry";
import {expectedInDrawer, shiftVarianceJournalLines} from "../../shared/ledger/shiftLines";

interface CloseShiftData {
  schoolId: string;
  shiftId: string;
  countedAmount: number;
  varianceNote?: string;
}

const CASHIER_ROLES = ["admin", "registrar"];

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * Counts a drawer and closes it.
 *
 * The expected figure is worked out **here**, from the payments this
 * cashier took while the shift was open, and never accepted from the
 * client. A count checked against a number the counter supplied is not
 * a control at all.
 *
 * It is then stored on the shift, so the figure the variance was struck
 * against cannot move afterwards -- a later refund backdated into the
 * window would otherwise silently rewrite last Tuesday's reckoning.
 */
export const closeCashierShift = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<CloseShiftData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, shiftId, countedAmount, varianceNote} = request.data ?? {};

    if (!schoolId || !shiftId || typeof countedAmount !== "number") {
      throw new HttpsError("invalid-argument", "Missing the counted amount.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!CASHIER_ROLES.includes(callerClaims.role)) {
      throw new HttpsError("permission-denied", "Only a cashier can close a drawer.");
    }
    if (!Number.isFinite(countedAmount) || countedAmount < 0) {
      throw new HttpsError("invalid-argument", "A count cannot be a negative amount.");
    }

    const db = admin.firestore();
    const shiftRef = db.doc(FirestorePaths.cashierShiftDoc(schoolId, shiftId));
    const snap = await shiftRef.get();
    const shift = snap.data();
    if (!shift) {
      throw new HttpsError("not-found", "That drawer is not on the list.");
    }
    if (shift.closedAt) {
      throw new HttpsError("failed-precondition", "That drawer is already closed.");
    }
    // A cashier counts their own drawer. An admin closing somebody
    // else's would put their name on a count they did not make.
    if (shift.cashierUid !== request.auth!.uid) {
      throw new HttpsError(
        "permission-denied",
        `That drawer belongs to ${shift.cashierName}. Only they can close it.`
      );
    }

    const openedAt = (shift.openedAt as admin.firestore.Timestamp | undefined)?.toDate();
    if (!openedAt) {
      // The open write stamps this from the server clock, so a shift
      // without it never round-tripped and has no window to reckon over.
      throw new HttpsError("failed-precondition", "That drawer has no opening time.");
    }
    const closingAt = new Date();

    // Every cash receipt this cashier wrote while the drawer was open.
    // A refund is stored as a payment with a negative amount, so summing
    // the amounts nets them off exactly as the drawer does.
    const receipts = await db
      .collection(FirestorePaths.payments(schoolId))
      .where("collectedBy", "==", shift.cashierUid)
      .where("method", "==", "cash")
      .where("isDeleted", "==", false)
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(openedAt))
      .where("createdAt", "<=", admin.firestore.Timestamp.fromDate(closingAt))
      .get();

    let cashCollected = 0;
    let cashRefunded = 0;
    for (const doc of receipts.docs) {
      const amount = (doc.data().amount as number) ?? 0;
      if (amount >= 0) {
        cashCollected += amount;
      } else {
        cashRefunded += Math.abs(amount);
      }
    }
    cashCollected = round2(cashCollected);
    cashRefunded = round2(cashRefunded);

    const expectedAmount = expectedInDrawer({
      openingFloat: (shift.openingFloat as number) ?? 0,
      cashCollected,
      cashRefunded,
      receiptCount: receipts.size,
    });
    const variance = round2(countedAmount - expectedAmount);

    // A difference with no explanation is the one thing an auditor will
    // ask about and the one thing nobody will remember. It does not have
    // to be a good reason, but it has to be a reason.
    const note = (varianceNote ?? "").trim();
    if (!sameMoney(variance, 0) && note.length < 4) {
      throw new HttpsError(
        "invalid-argument",
        `The drawer is ${variance < 0 ? "short" : "over"} by ` +
          `${Math.abs(variance).toFixed(2)}. Say what happened.`
      );
    }

    const lines = shiftVarianceJournalLines(variance);
    const closedByName = (request.auth!.token.name as string) ?? "Unknown";
    let journalEntryId: string | null = null;

    if (lines.length > 0) {
      await ensureChartOfAccounts(schoolId, STANDARD_CHART);
      const sequence = await getNextSequence(schoolId, "journalEntryNumber");
      await db.runTransaction(async (tx) => {
        const fresh = await tx.get(shiftRef);
        if (fresh.data()?.closedAt) {
          throw new HttpsError(
            "failed-precondition",
            "That drawer was closed while this count was being taken."
          );
        }
        const entry = postJournalEntryInTransaction(
          tx,
          {
            schoolId,
            date: closingAt,
            memo: `Cash ${variance < 0 ? "short" : "over"} - ` +
              `${shift.cashierName} drawer: ${note}`,
            source: "manual",
            sourceId: shiftId,
            postedBy: request.auth!.uid,
            postedByName: closedByName,
            lines,
          },
          sequence
        );
        journalEntryId = entry.id;
        tx.update(shiftRef, {
          closedAt: admin.firestore.Timestamp.fromDate(closingAt),
          countedAmount,
          expectedAmount,
          varianceNote: note || null,
          closedByName,
          journalEntryId: entry.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.auth!.uid,
        });
      });
    } else {
      // A drawer that balances posts nothing. There is no entry to make
      // and an entry of nothing is refused anyway.
      await shiftRef.update({
        closedAt: admin.firestore.Timestamp.fromDate(closingAt),
        countedAmount,
        expectedAmount,
        varianceNote: note || null,
        closedByName,
        journalEntryId: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: closedByName,
      module: "cashiering",
      action: "shift_closed",
      targetCollection: FirestorePaths.cashierShifts(schoolId),
      targetId: shiftId,
      newValue: {countedAmount, expectedAmount, variance, note: note || null},
      success: true,
    });

    return {
      expectedAmount,
      variance,
      cashCollected,
      cashRefunded,
      receiptCount: receipts.size,
      journalEntryId,
    };
  }
);
