import {Accounts} from "../../../src/shared/ledger/accounts";
import {reasonEntryCannotPost} from "../../../src/shared/ledger/postJournalEntry";
import {
  billJournalLines,
  billPaymentJournalLines,
  billTotal,
  expenseJournalLines,
  voidBillJournalLines,
} from "../../../src/shared/ledger/billLines";
import {accountForExpenseCategory} from "../../../src/triggers/payables/onExpenseRecorded";

const lines = [
  {accountCode: Accounts.expenseSupplies, description: "Bond paper", amount: 3000},
  {accountCode: Accounts.expenseUtilities, description: "Water delivery", amount: 2000},
];

describe("recording a bill", () => {
  it("adds the lines up", () => {
    expect(billTotal(lines)).toBe(5000);
    expect(billTotal([])).toBe(0);
  });

  it("debits what was bought and credits one payable", () => {
    // What was bought is an expense the moment it is delivered, not the
    // day it is paid for -- that is the whole of why AP exists as
    // something separate from a cash book.
    const entry = billJournalLines(lines);

    expect(reasonEntryCannotPost(entry)).toBeNull();
    expect(entry.filter((l) => l.debit)).toHaveLength(2);

    // One credit line, not one per expense line: the school owes the
    // vendor one amount and will pay it with one cheque.
    const credits = entry.filter((l) => l.credit);
    expect(credits).toHaveLength(1);
    expect(credits[0].accountCode).toBe(Accounts.payableTrade);
    expect(credits[0].credit).toBe(5000);
  });

  it("carries each line's description onto its journal line", () => {
    // So the ledger says "Bond paper", not "Invoice SI-99321" five times.
    const entry = billJournalLines(lines);
    expect(entry[0].memo).toBe("Bond paper");
    expect(entry[1].memo).toBe("Water delivery");
  });

  it("balances a bill with centavos on every line", () => {
    const awkward = [
      {accountCode: Accounts.expenseSupplies, description: "a", amount: 333.33},
      {accountCode: Accounts.expenseSupplies, description: "b", amount: 333.33},
      {accountCode: Accounts.expenseSupplies, description: "c", amount: 333.34},
    ];
    expect(reasonEntryCannotPost(billJournalLines(awkward))).toBeNull();
  });
});

describe("paying a bill", () => {
  it("debits the liability away and credits the cash", () => {
    const entry = billPaymentJournalLines(2000, Accounts.cashInBank);

    expect(reasonEntryCannotPost(entry)).toBeNull();
    expect(entry.find((l) => l.accountCode === Accounts.payableTrade)?.debit).toBe(2000);
    expect(entry.find((l) => l.accountCode === Accounts.cashInBank)?.credit).toBe(2000);
  });

  it("touches no expense account at all", () => {
    // The expense was recognised when the bill was recorded. Touching it
    // again here is the double-count that makes a year's expenses read
    // twice what the school actually spent.
    const entry = billPaymentJournalLines(2000, Accounts.cashOnHand);
    expect(entry.some((l) => l.accountCode.startsWith("5"))).toBe(false);
  });

  it("a part payment balances like any other", () => {
    expect(reasonEntryCannotPost(billPaymentJournalLines(1234.56, Accounts.eWallet)))
      .toBeNull();
  });
});

describe("voiding a bill", () => {
  it("is the exact opposite of recording it", () => {
    const recorded = billJournalLines(lines);
    const voided = voidBillJournalLines(lines);

    expect(reasonEntryCannotPost(voided)).toBeNull();
    expect(voided.find((l) => l.accountCode === Accounts.payableTrade)?.debit).toBe(5000);

    // Every expense line that was debited is now credited by the same
    // amount, so the pair nets to nothing.
    const debitedOnRecord = recorded
      .filter((l) => l.debit)
      .reduce((sum, l) => sum + (l.debit ?? 0), 0);
    const creditedOnVoid = voided
      .filter((l) => l.credit)
      .reduce((sum, l) => sum + (l.credit ?? 0), 0);
    expect(creditedOnVoid).toBe(debitedOnRecord);
  });
});

describe("a direct expense", () => {
  it("moves the expense and the cash at the same moment", () => {
    // No liability in between: the sari-sari store down the road is paid
    // when the chalk is handed over.
    const entry = expenseJournalLines(850, Accounts.expenseSupplies, Accounts.cashOnHand);

    expect(reasonEntryCannotPost(entry)).toBeNull();
    expect(entry).toHaveLength(2);
    expect(entry[0].debit).toBe(850);
    expect(entry[1].credit).toBe(850);
    expect(entry.some((l) => l.accountCode === Accounts.payableTrade)).toBe(false);
  });

  it("maps each category on the expenses screen to a real account", () => {
    expect(accountForExpenseCategory("Utilities")).toBe(Accounts.expenseUtilities);
    expect(accountForExpenseCategory("Supplies")).toBe(Accounts.expenseSupplies);
    expect(accountForExpenseCategory("Maintenance")).toBe(Accounts.expenseRepairs);
    expect(accountForExpenseCategory("Salaries")).toBe(Accounts.expenseSalaries);
    // Case and spacing are whatever somebody typed.
    expect(accountForExpenseCategory("  utilities ")).toBe(Accounts.expenseUtilities);
  });

  it("puts anything it does not recognise somewhere visible", () => {
    // Visible and wrong beats invisible and wrong: a school that spends
    // enough on transport to care adds an account and recodes.
    expect(accountForExpenseCategory("Transportation")).toBe(Accounts.expenseOther);
    expect(accountForExpenseCategory("Something new")).toBe(Accounts.expenseOther);
    expect(accountForExpenseCategory("")).toBe(Accounts.expenseOther);
  });
});
