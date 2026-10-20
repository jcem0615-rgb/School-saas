import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {Accounts, STANDARD_CHART} from "../../shared/ledger/accounts";
import {
  ensureChartOfAccounts,
  postJournalEntryInTransaction,
} from "../../shared/ledger/postJournalEntry";
import {expenseJournalLines} from "../../shared/ledger/billLines";

/**
 * Which account a category of spending belongs to.
 *
 * The categories are the six on the expenses screen. A school that types
 * something else gets Other Expenses, which is visible and wrong rather
 * than invisible and wrong.
 */
export function accountForExpenseCategory(category: string): string {
  switch ((category ?? "").trim().toLowerCase()) {
  case "utilities": return Accounts.expenseUtilities;
  case "supplies": return Accounts.expenseSupplies;
  case "maintenance": return Accounts.expenseRepairs;
  case "salaries": return Accounts.expenseSalaries;
  // Transportation has no account of its own in the standard chart. A
  // school that spends enough on it to care adds 5400 and recodes --
  // which is a thing they can see and do, unlike a silent miscoding.
  default: return Accounts.expenseOther;
  }
}

/**
 * Posts a direct expense to the books.
 *
 * ## Why a trigger, when nothing else here is one
 *
 * Every other posting happens inside the transaction that writes the
 * thing being accounted for, and that is the better design: the entry
 * and the record commit together or neither does.
 *
 * Expenses are the exception because they are written by the client --
 * the Director's expenses screen writes the document straight to
 * Firestore, and has since long before there were books to post to.
 * Routing it through a callable would be the tidier answer and is worth
 * doing; until then, a trigger is the honest one. What it gives up is
 * atomicity: for a moment after the expense is written, the books do not
 * know about it, and if this function fails every retry it never will.
 *
 * ## Why that is survivable
 *
 * The entry carries `sourceId: expenseId`, and the write is skipped if
 * an entry already cites it. Firestore triggers are at-least-once, so
 * without that check a retried delivery would post the same expense
 * twice -- which is worse than posting it late.
 *
 * A bill is not this. Money the school owes goes through recordBill,
 * which posts inside its own transaction.
 */
export const onExpenseRecorded = onDocumentCreated(
  {document: "schools/{schoolId}/expenses/{expenseId}", region: "asia-southeast1"},
  async (event) => {
    const expense = event.data?.data();
    if (!expense) return;

    const {schoolId, expenseId} = event.params;
    const amount = (expense.amount as number) ?? 0;
    if (!(amount > 0)) return;
    if (expense.isDeleted === true) return;

    const db = admin.firestore();

    // At-least-once delivery: a retried event must not post the expense
    // a second time. The source id is the idempotency key.
    const already = await db
      .collection(FirestorePaths.journalEntries(schoolId))
      .where("source", "==", "expense")
      .where("sourceId", "==", expenseId)
      .limit(1)
      .get();
    if (!already.empty) return;

    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const sequence = await getNextSequence(schoolId, "journalEntryNumber");

    const spentOn = (expense.date as admin.firestore.Timestamp | undefined)?.toDate()
      ?? new Date();
    const description = (expense.description as string) ?? "Expense";

    await db.runTransaction(async (tx) => {
      postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          date: spentOn,
          memo: description,
          source: "expense",
          sourceId: expenseId,
          postedBy: (expense.createdBy as string) ?? "system",
          postedByName: (expense.recordedByName as string) ?? "Unknown",
          lines: expenseJournalLines(
            amount,
            accountForExpenseCategory(expense.category as string),
            // Direct spending comes out of the bank unless the school
            // says otherwise. The expenses screen does not ask, so this
            // is an assumption rather than a fact -- and one a school
            // reconciling its bank statement will correct by recoding.
            Accounts.cashInBank
          ),
        },
        sequence
      );
    });
  }
);
