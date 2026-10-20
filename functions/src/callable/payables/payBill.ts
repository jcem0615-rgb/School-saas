import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {Accounts, STANDARD_CHART} from "../../shared/ledger/accounts";
import {
  ensureChartOfAccounts,
  postJournalEntryInTransaction,
  sameMoney,
} from "../../shared/ledger/postJournalEntry";
import {billPaymentJournalLines} from "../../shared/ledger/billLines";

interface PayBillData {
  schoolId: string;
  billId: string;
  amount: number;
  /** Which cash account it came out of: 1000, 1010, 1020. */
  paidFromAccountCode: string;
  date?: string;
  /** Cheque number, transfer reference -- what the bank statement says. */
  reference?: string;
}

const PAYABLES_ROLES = ["director", "admin"];

/** The accounts money can actually leave from. */
const CASH_ACCOUNTS = [Accounts.cashOnHand, Accounts.cashInBank, Accounts.eWallet];

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * Pays a bill, in full or in part.
 *
 * The balance is read inside the transaction, not from a snapshot taken
 * before it. Two people paying the same bill at the same moment both
 * read the same outstanding figure otherwise, and the second write lands
 * on top of the first -- a supplier paid twice, with the ledger showing
 * one payment. The same reason recordPayment reads a student's balance
 * inside its transaction.
 */
export const payBill = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<PayBillData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, billId, amount, paidFromAccountCode, date, reference} =
      request.data ?? {};

    if (!schoolId || !billId || !(amount > 0) || !paidFromAccountCode) {
      throw new HttpsError("invalid-argument", "Missing payment details.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!PAYABLES_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the Director or an Admin can pay a bill."
      );
    }
    if (!CASH_ACCOUNTS.includes(paidFromAccountCode as typeof CASH_ACCOUNTS[number])) {
      // Money has to come out of somewhere money actually sits. Crediting
      // an expense account here would balance and quietly reverse part
      // of a cost the school really incurred.
      throw new HttpsError(
        "invalid-argument",
        "Choose the cash, bank or e-wallet account the money came out of."
      );
    }

    const paidOn = date ? new Date(date) : new Date();
    if (Number.isNaN(paidOn.getTime())) {
      throw new HttpsError("invalid-argument", "That is not a date.");
    }
    if (paidOn.getTime() > Date.now() + 24 * 60 * 60 * 1000) {
      throw new HttpsError("invalid-argument", "A payment cannot be dated in the future.");
    }

    const db = admin.firestore();
    const billRef = db.doc(FirestorePaths.billDoc(schoolId, billId));
    const first = await billRef.get();
    if (!first.exists) {
      throw new HttpsError("not-found", "That bill is not on the list.");
    }

    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const journalSequence = await getNextSequence(schoolId, "journalEntryNumber");
    const paidByName = (request.auth!.token.name as string) ?? "Unknown";
    const paymentId = db.collection(FirestorePaths.bills(schoolId)).doc().id;

    let outstandingAfter = 0;
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(billRef);
      const bill = fresh.data();
      if (!bill) {
        throw new HttpsError("not-found", "That bill is not on the list.");
      }
      if (bill.voidedAt) {
        throw new HttpsError("failed-precondition", "That bill was voided.");
      }

      const total = (bill.total as number) ?? 0;
      const alreadyPaid = (bill.amountPaid as number) ?? 0;
      const outstanding = round2(total - alreadyPaid);
      if (outstanding <= 0 || sameMoney(outstanding, 0)) {
        throw new HttpsError("failed-precondition", "That bill is already settled.");
      }
      // Overpaying is almost always a typo, and letting it through turns
      // one mistake into a wrong figure on every report that sums what
      // is outstanding.
      if (amount - outstanding > 0.005) {
        throw new HttpsError(
          "invalid-argument",
          `That is more than the ${outstanding.toFixed(2)} still owed on this bill.`
        );
      }

      const nowPaid = round2(alreadyPaid + amount);
      outstandingAfter = round2(total - nowPaid);

      const entry = postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          date: paidOn,
          memo: `Payment to ${bill.vendorName} for ${bill.billNumber}`,
          source: "bill_payment",
          sourceId: billId,
          postedBy: request.auth!.uid,
          postedByName: paidByName,
          lines: billPaymentJournalLines(amount, paidFromAccountCode),
        },
        journalSequence
      );

      tx.update(billRef, {
        amountPaid: nowPaid,
        status: sameMoney(outstandingAfter, 0) ? "paid" : "partially_paid",
        // Appended rather than replaced: the history of how a bill was
        // settled is the thing a supplier rings up about.
        payments: admin.firestore.FieldValue.arrayUnion({
          id: paymentId,
          date: admin.firestore.Timestamp.fromDate(paidOn),
          amount: round2(amount),
          paidFromAccountCode,
          reference: reference?.trim() || null,
          paidBy: request.auth!.uid,
          paidByName,
          journalEntryId: entry.id,
        }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: paidByName,
      module: "payables",
      action: "bill_paid",
      targetCollection: FirestorePaths.bills(schoolId),
      targetId: billId,
      newValue: {amount, paidFromAccountCode, reference: reference ?? null},
      success: true,
    });

    return {paymentId, outstanding: outstandingAfter};
  }
);
