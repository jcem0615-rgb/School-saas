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
import {BillLineInput, billJournalLines, billTotal} from "../../shared/ledger/billLines";

interface RecordBillData {
  schoolId: string;
  vendorId: string;
  /** The number printed on the supplier's invoice, not one we generate. */
  billNumber: string;
  billDate: string;
  dueDate: string;
  lines: BillLineInput[];
  notes?: string;
}

/** Who may enter what the school owes. The same pair that keeps the books. */
const PAYABLES_ROLES = ["director", "admin"];

/**
 * Records a bill, and the liability it creates.
 *
 * A callable rather than a client write for the same reason the journal
 * is: the entry raised here has to balance and has to commit with the
 * bill, and security rules cannot sum an array. Entering a bill and
 * posting its entry separately is how a payables ledger ends up
 * disagreeing with the books.
 */
export const recordBill = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordBillData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, vendorId, billNumber, billDate, dueDate, lines, notes} =
      request.data ?? {};

    if (!schoolId || !vendorId || !billNumber || !billDate || !dueDate || !Array.isArray(lines)) {
      throw new HttpsError("invalid-argument", "Missing bill details.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!PAYABLES_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the Director or an Admin can enter a bill."
      );
    }
    if (lines.length === 0) {
      throw new HttpsError("invalid-argument", "A bill needs at least one line.");
    }
    for (const line of lines) {
      if (!line.accountCode?.trim() || !line.description?.trim() || !(line.amount > 0)) {
        throw new HttpsError(
          "invalid-argument",
          "Every line needs an account, a description and an amount above zero."
        );
      }
    }

    const issued = new Date(billDate);
    const due = new Date(dueDate);
    if (Number.isNaN(issued.getTime()) || Number.isNaN(due.getTime())) {
      throw new HttpsError("invalid-argument", "That is not a date.");
    }
    if (due.getTime() < new Date(issued.toDateString()).getTime()) {
      throw new HttpsError("invalid-argument", "A bill cannot fall due before it was issued.");
    }

    const db = admin.firestore();
    const vendorSnap = await db.doc(FirestorePaths.vendorDoc(schoolId, vendorId)).get();
    if (!vendorSnap.exists) {
      throw new HttpsError("not-found", "That supplier is not on the list.");
    }
    const vendor = vendorSnap.data()!;

    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const chart = await db.collection(FirestorePaths.ledgerAccounts(schoolId)).get();
    const known = new Map(chart.docs.map((d) => [d.id, d.data()]));
    for (const line of lines) {
      const account = known.get(line.accountCode.trim());
      if (!account) {
        throw new HttpsError(
          "invalid-argument",
          `There is no account ${line.accountCode} in the chart.`
        );
      }
      // A bill buys something. Coding one to revenue or to a payable
      // balances and means nothing -- and nobody reading the expense
      // report later would be able to tell why it is short.
      if (account.type !== "expense" && account.type !== "asset") {
        throw new HttpsError(
          "invalid-argument",
          `${line.accountCode} - ${account.name} is not something a bill can buy.`
        );
      }
    }

    // The same invoice entered twice is the most common mistake in a
    // payables ledger, and it pays a supplier twice.
    const duplicate = await db
      .collection(FirestorePaths.bills(schoolId))
      .where("vendorId", "==", vendorId)
      .where("billNumber", "==", billNumber.trim())
      .where("isDeleted", "==", false)
      .limit(1)
      .get();
    if (!duplicate.empty) {
      throw new HttpsError(
        "already-exists",
        `${vendor.name} invoice ${billNumber.trim()} is already recorded.`
      );
    }

    const total = billTotal(lines);
    const billRef = db.collection(FirestorePaths.bills(schoolId)).doc();
    const journalSequence = await getNextSequence(schoolId, "journalEntryNumber");
    const postedByName = (request.auth!.token.name as string) ?? "Unknown";

    await db.runTransaction(async (tx) => {
      const entry = postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          date: issued,
          memo: `${vendor.name} invoice ${billNumber.trim()}`,
          source: "bill",
          sourceId: billRef.id,
          postedBy: request.auth!.uid,
          postedByName,
          lines: billJournalLines(
            lines.map((l) => ({
              ...l,
              accountName: known.get(l.accountCode.trim())?.name as string | undefined,
            }))
          ),
        },
        journalSequence
      );

      tx.set(billRef, {
        id: billRef.id,
        schoolId,
        vendorId,
        // Denormalised, like every other name here: a supplier renamed
        // next year must not rewrite what last year's voucher said.
        vendorName: vendor.name,
        billNumber: billNumber.trim(),
        billDate: admin.firestore.Timestamp.fromDate(issued),
        dueDate: admin.firestore.Timestamp.fromDate(due),
        lines: lines.map((l) => ({
          accountCode: l.accountCode.trim(),
          accountName: known.get(l.accountCode.trim())?.name ?? "Unknown account",
          description: l.description.trim(),
          amount: l.amount,
        })),
        total,
        amountPaid: 0,
        status: "open",
        notes: notes?.trim() || null,
        journalEntryId: entry.id,
        payments: [],
        recordedBy: request.auth!.uid,
        recordedByName: postedByName,
        recordedAt: admin.firestore.FieldValue.serverTimestamp(),
        voidedAt: null,
        voidedByName: null,
        voidReason: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: request.auth!.uid,
        isDeleted: false,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: postedByName,
      module: "payables",
      action: "bill_recorded",
      targetCollection: FirestorePaths.bills(schoolId),
      targetId: billRef.id,
      newValue: {vendorName: vendor.name, billNumber: billNumber.trim(), total},
      success: true,
    });

    return {billId: billRef.id, total};
  }
);
