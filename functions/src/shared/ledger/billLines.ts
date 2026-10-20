import {Accounts} from "./accounts";
import {JournalLineInput} from "./postJournalEntry";

export interface BillLineInput {
  accountCode: string;
  accountName?: string;
  description: string;
  amount: number;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function billTotal(lines: BillLineInput[]): number {
  return round2(lines.reduce((sum, l) => sum + (l.amount ?? 0), 0));
}

/**
 * The entry a bill raises.
 *
 * What was bought is an expense the moment it is delivered, not the day
 * it is paid for -- that is the whole of accrual accounting and the only
 * reason accounts payable exists as a thing separate from a cash book.
 * So: debit whatever was bought, credit Accounts Payable.
 *
 * One credit line, not one per expense line. The school owes the vendor
 * one amount and will pay it with one cheque; splitting the liability
 * across four lines would make the payables ledger unreadable for no
 * gain.
 */
export function billJournalLines(lines: BillLineInput[]): JournalLineInput[] {
  const total = billTotal(lines);
  return [
    ...lines.map((l) => ({
      accountCode: l.accountCode,
      accountName: l.accountName,
      debit: round2(l.amount),
      memo: l.description,
    })),
    {accountCode: Accounts.payableTrade, credit: total},
  ];
}

/**
 * The entry a payment against a bill makes.
 *
 * Debit the liability away, credit the cash it came out of. No expense
 * is touched: that was recognised when the bill was recorded, and
 * touching it again here is the double-count that makes a year's
 * expenses read twice what the school actually spent.
 */
export function billPaymentJournalLines(
  amount: number,
  paidFromAccountCode: string
): JournalLineInput[] {
  const paid = round2(amount);
  return [
    {accountCode: Accounts.payableTrade, debit: paid},
    {accountCode: paidFromAccountCode, credit: paid},
  ];
}

/**
 * The entry that reverses a bill being voided.
 *
 * A void is not a deletion: the bill and its entry both stay, and this
 * undoes the liability. Only ever called for a bill with nothing paid
 * against it -- one that has been part paid has to be settled or
 * credited, not made to disappear, because the cash really did leave.
 */
export function voidBillJournalLines(lines: BillLineInput[]): JournalLineInput[] {
  const total = billTotal(lines);
  return [
    {accountCode: Accounts.payableTrade, debit: total},
    ...lines.map((l) => ({
      accountCode: l.accountCode,
      accountName: l.accountName,
      credit: round2(l.amount),
      memo: l.description,
    })),
  ];
}

/**
 * The entry a direct expense makes -- money out with no bill behind it.
 *
 * The sari-sari store down the road, the tricycle fare to the division
 * office. There is no liability in between: the expense and the cash
 * move at the same moment.
 */
export function expenseJournalLines(
  amount: number,
  expenseAccountCode: string,
  paidFromAccountCode: string
): JournalLineInput[] {
  const spent = round2(amount);
  return [
    {accountCode: expenseAccountCode, debit: spent},
    {accountCode: paidFromAccountCode, credit: spent},
  ];
}
