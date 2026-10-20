import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {FirestorePaths} from "../firestore-paths";
import {ACCOUNT_NAMES} from "./accounts";

export type EntrySource =
  | "payment"
  | "refund"
  | "assessment"
  | "payroll"
  | "expense"
  | "bill"
  | "bill_payment"
  | "manual"
  | "reversal";

export interface JournalLineInput {
  accountCode: string;
  /** Falls back to the seeded name for the code. */
  accountName?: string;
  debit?: number;
  credit?: number;
  memo?: string;
}

export interface PostEntryInput {
  schoolId: string;
  date: Date;
  memo: string;
  source: EntrySource;
  sourceId?: string | null;
  lines: JournalLineInput[];
  postedBy: string;
  postedByName: string;
  reversalOf?: string | null;
}

/**
 * Money is counted in centavos, and a double is not.
 *
 * 0.1 + 0.2 is not 0.3 in binary floating point, and a journal is exactly
 * where that shows up. Everything here compares to the nearest centavo.
 */
const CENTAVO = 0.005;

export function sameMoney(a: number, b: number): boolean {
  return Math.abs(a - b) < CENTAVO;
}

/** Rounds to centavos, so what is stored is what a receipt can show. */
function toCentavos(amount: number): number {
  return Math.round(amount * 100) / 100;
}

/**
 * Why a set of lines may not be posted, or null.
 *
 * A string rather than a bool because every one of these ends up in
 * front of a person, and "invalid entry" is not worth saying.
 */
export function reasonEntryCannotPost(lines: JournalLineInput[]): string | null {
  if (!Array.isArray(lines) || lines.length < 2) {
    return "An entry needs at least two lines: what was given and what was got.";
  }
  for (const line of lines) {
    const debit = line.debit ?? 0;
    const credit = line.credit ?? 0;
    if (!line.accountCode || !line.accountCode.trim()) {
      return "Every line needs an account.";
    }
    if (debit < 0 || credit < 0) {
      return "A line cannot be negative. Put it on the other side instead.";
    }
    if ((debit > 0) === (credit > 0)) {
      return "Every line has to be a debit or a credit, and more than zero.";
    }
  }
  const debits = lines.reduce((sum, l) => sum + (l.debit ?? 0), 0);
  const credits = lines.reduce((sum, l) => sum + (l.credit ?? 0), 0);
  if (!sameMoney(debits, credits)) {
    return `Debits and credits differ by ${Math.abs(debits - credits).toFixed(2)}. ` +
      "An entry has to balance.";
  }
  if (debits <= 0) {
    return "An entry of nothing is not an entry.";
  }
  return null;
}

/** JE-2026-0042. What gets quoted in an audit. */
export function formatEntryNumber(sequence: number, year: number): string {
  return `JE-${year}-${String(sequence).padStart(4, "0")}`;
}

/**
 * Writes one journal entry inside a transaction already in progress.
 *
 * Transaction-scoped on purpose, and it is the whole design. The entry
 * and the thing that caused it -- the payment, the payslip, the bill --
 * commit together or neither does. A ledger posted afterwards, in a
 * trigger or a second write, is a ledger that disagrees with the receipt
 * every time the second write fails, and reconciling the two is the week
 * this product exists to give back.
 *
 * The caller passes the sequence because claiming a number needs its own
 * transaction, and Firestore will not nest them. Claim it first, as
 * recordPayment already does for receipt numbers.
 */
export function postJournalEntryInTransaction(
  tx: admin.firestore.Transaction,
  input: PostEntryInput,
  sequence: number
): {id: string; entryNumber: string} {
  const problem = reasonEntryCannotPost(input.lines);
  if (problem) {
    // An unbalanced posting is a bug in the caller, not bad input from a
    // person. Failing loudly here is the only thing that keeps the books
    // honest -- the alternative is a journal that silently does not add
    // up and an accountant who finds out in March.
    throw new HttpsError("internal", `Refusing to post an unbalanced entry: ${problem}`);
  }

  const db = admin.firestore();
  const ref = db.collection(FirestorePaths.journalEntries(input.schoolId)).doc();
  const entryNumber = formatEntryNumber(sequence, input.date.getFullYear());

  tx.set(ref, {
    id: ref.id,
    schoolId: input.schoolId,
    entryNumber,
    date: admin.firestore.Timestamp.fromDate(input.date),
    memo: input.memo,
    source: input.source,
    sourceId: input.sourceId ?? null,
    lines: input.lines.map((l) => ({
      accountCode: l.accountCode.trim(),
      // Denormalised at the moment of posting: a school that renames
      // 5100 from "Utilities" to "Light and Water" should not have last
      // year's vouchers silently re-captioned.
      accountName: l.accountName ?? ACCOUNT_NAMES[l.accountCode.trim()] ?? "Unknown account",
      debit: toCentavos(l.debit ?? 0),
      credit: toCentavos(l.credit ?? 0),
      memo: l.memo ?? null,
    })),
    totalDebits: toCentavos(input.lines.reduce((s, l) => s + (l.debit ?? 0), 0)),
    totalCredits: toCentavos(input.lines.reduce((s, l) => s + (l.credit ?? 0), 0)),
    postedBy: input.postedBy,
    postedByName: input.postedByName,
    postedAt: admin.firestore.FieldValue.serverTimestamp(),
    reversalOf: input.reversalOf ?? null,
    reversedBy: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: input.postedBy,
    isDeleted: false,
  });

  return {id: ref.id, entryNumber};
}

/**
 * Seeds the chart of accounts if the school has none.
 *
 * Idempotent, and deliberately not a migration: a school that has
 * renamed 4010 keeps its name, because the write only touches codes that
 * are not there. Called the first time anything posts, so a school that
 * never opens the finance screens never grows a chart it did not ask for.
 */
export async function ensureChartOfAccounts(
  schoolId: string,
  chart: {code: string; name: string; type: string; isSystem: boolean; description?: string}[]
): Promise<void> {
  const db = admin.firestore();
  const collection = db.collection(FirestorePaths.ledgerAccounts(schoolId));
  const existing = await collection.get();
  if (!existing.empty) return;

  const batch = db.batch();
  for (const account of chart) {
    batch.set(collection.doc(account.code), {
      code: account.code,
      name: account.name,
      type: account.type,
      isSystem: account.isSystem,
      isActive: true,
      description: account.description ?? null,
      schoolId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isDeleted: false,
    });
  }
  await batch.commit();
}
