import {Accounts} from "./accounts";
import {JournalLineInput} from "./postJournalEntry";

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export interface ShiftTally {
  openingFloat: number;
  cashCollected: number;
  cashRefunded: number;
  receiptCount: number;
}

/**
 * What should be in a drawer.
 *
 * Refunds come back out of the same money, so a reckoning that ignored
 * them would read short by exactly the refunds, every time one happened.
 */
export function expectedInDrawer(tally: ShiftTally): number {
  return round2(tally.openingFloat + tally.cashCollected - tally.cashRefunded);
}

/**
 * The entry a drawer's difference makes.
 *
 * Returns an empty list when the drawer balances: posting a pair of
 * zero lines would be a journal entry that says nothing, and an entry
 * of nothing is refused anyway.
 *
 * Short means the cash account has less in it than the books think, so
 * the books come down and the difference is a cost. Over is the same
 * thing backwards -- and over is not good news, it is the same control
 * failing in the other direction, which is why both land in one account
 * somebody can look at.
 */
export function shiftVarianceJournalLines(variance: number): JournalLineInput[] {
  const amount = round2(Math.abs(variance));
  if (amount < 0.005) return [];

  return variance < 0
    ? [
      {accountCode: Accounts.expenseCashVariance, debit: amount},
      {accountCode: Accounts.cashOnHand, credit: amount},
    ]
    : [
      {accountCode: Accounts.cashOnHand, debit: amount},
      {accountCode: Accounts.expenseCashVariance, credit: amount},
    ];
}
