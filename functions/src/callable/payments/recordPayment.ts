import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {applyPayment, formatReceiptNumber} from "../../shared/payments/balanceMath";
import {claimOfficialReceipt} from "../../shared/payments/officialReceipt";
import {Accounts, STANDARD_CHART, cashAccountForMethod} from "../../shared/ledger/accounts";
import {
  ensureChartOfAccounts,
  postJournalEntryInTransaction,
} from "../../shared/ledger/postJournalEntry";

interface RecordPaymentData {
  schoolId: string;
  studentId: string;
  amount: number;
  method: "cash" | "gcash" | "bank_transfer" | "online";
  referenceNumber?: string;
  purpose: "tuition" | "misc_fee" | "other";
  /**
   * The number pre-printed on the BIR official receipt handed over.
   * Required when the school has a booklet registered, ignored -- and
   * refused if sent -- when it has not.
   */
  officialReceiptNo?: number;
}

// Roles that may collect/record a payment. Faculty/Staff/Guidance have no
// business handling money -- keeping this list tight limits blast radius
// if any one account is compromised.
const COLLECTOR_ALLOWED_ROLES = ["admin", "registrar"];

/**
 * Payments are recorded by collectors only.
 *
 * Students and parents deliberately cannot reach this. They file a
 * paymentSubmission instead, and decidePaymentSubmission creates the
 * Payment once a cashier has verified the reference against the school's
 * e-wallet. Letting them call this directly would let anyone credit their
 * own balance by asserting they had paid, which is exactly what the
 * review step exists to prevent.
 */
async function authorizePayer(
  callerRole: string
): Promise<void> {
  if (!COLLECTOR_ALLOWED_ROLES.includes(callerRole)) {
    throw new HttpsError(
      "permission-denied",
      "Only a cashier can record a payment. Submit it for review instead."
    );
  }
}

export const recordPayment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordPaymentData>) => {
    const callerClaims = requireCallerClaims(request);

    const {schoolId, studentId, amount, method, referenceNumber, purpose, officialReceiptNo} =
      request.data;
    if (!schoolId || !studentId || !amount || amount <= 0 || !method || !purpose) {
      throw new HttpsError("invalid-argument", "Missing or invalid payment details.");
    }
    requireSameSchool(callerClaims, schoolId);
    if ((method === "gcash" || method === "bank_transfer") && !referenceNumber) {
      throw new HttpsError("invalid-argument", "A reference number is required for this payment method.");
    }

    const db = admin.firestore();
    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, studentId));
    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      throw new HttpsError("not-found", "Student record not found.");
    }
    // Authorization happens after the student is known to exist, so a
    // mistyped id fails as not-found rather than as a permission error.
    await authorizePayer(callerClaims.role);

    const sequence = await getNextSequence(schoolId, "receiptNumber");
    const receiptNumber = formatReceiptNumber(sequence, new Date().getFullYear());

    // The books are posted from the payment, not typed up afterwards.
    // Claimed out here because Firestore will not nest transactions, the
    // same reason the receipt number is. A failed transaction leaves a
    // gap in the journal numbering, which is what a paper journal does
    // with a spoiled page and what an auditor expects to see explained.
    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const journalSequence = await getNextSequence(schoolId, "journalEntryNumber");

    const paymentRef = db.collection(FirestorePaths.payments(schoolId)).doc();

    // The balance is read inside the transaction, not from the snapshot
    // fetched above. Two cashiers taking money from two families at the
    // same counter both read the same starting figure otherwise, and the
    // second write lands on top of the first -- one payment receipted,
    // banked, and not deducted. Reading here makes Firestore retry the
    // transaction instead, which is the whole reason it exists.
    //
    // The snapshot above is still worth having: it fails a bad student id
    // before a receipt number is burned from the counter.
    let newBalance = 0;
    let claimedReceipt: {number: number; formatted: string} | null = null;
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(studentRef);
      if (!fresh.exists) {
        throw new HttpsError("not-found", "Student record not found.");
      }
      // Inside the transaction, before the payment is written: the number
      // and the payment that cites it are committed together or neither
      // is. Claiming it outside would burn a number on a payment that
      // then failed to write.
      claimedReceipt = await claimOfficialReceipt(
        tx,
        schoolId,
        officialReceiptNo,
        paymentRef.id
      );
      newBalance = applyPayment((fresh.data()?.balance as number) ?? 0, amount);

      tx.set(paymentRef, {
        id: paymentRef.id,
        schoolId,
        studentId,
        amount,
        method,
        referenceNumber: referenceNumber ?? null,
        receiptNumber,
        officialReceiptNo: claimedReceipt ? claimedReceipt.number : null,
        collectedBy: request.auth!.uid,
        collectedByName: (request.auth!.token.name as string) ?? "Unknown",
        purpose,
        status: "completed",
        refundOf: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: request.auth!.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
        deletedAt: null,
        deletedBy: null,
        isDeleted: false,
      });
      tx.update(studentRef, {
        balance: newBalance,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });

      // Money in, and a receivable settled. The fee was earned when it
      // was assessed -- that is where the revenue was recognised -- so
      // collecting it moves an asset, it does not create income. Posting
      // revenue here as well would count every peso twice.
      //
      // Inside the same transaction as the payment: the entry and the
      // receipt commit together or neither does.
      postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          date: new Date(),
          memo: `Collection ${receiptNumber}`,
          source: "payment",
          sourceId: paymentRef.id,
          postedBy: request.auth!.uid,
          postedByName: (request.auth!.token.name as string) ?? "Unknown",
          lines: [
            {accountCode: cashAccountForMethod(method), debit: amount},
            {accountCode: Accounts.receivableStudents, credit: amount},
          ],
        },
        journalSequence
      );
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "payments",
      action: "payment_recorded",
      targetCollection: FirestorePaths.payments(schoolId),
      targetId: paymentRef.id,
      newValue: {
        studentId,
        amount,
        method,
        receiptNumber,
        officialReceiptNo: claimedReceipt ? (claimedReceipt as {formatted: string}).formatted : null,
      },
      success: true,
    });

    return {
      paymentId: paymentRef.id,
      receiptNumber,
      officialReceiptNo: claimedReceipt ? (claimedReceipt as {formatted: string}).formatted : null,
      newBalance,
    };
  }
);
