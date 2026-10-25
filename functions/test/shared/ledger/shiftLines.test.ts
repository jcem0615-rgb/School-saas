import {Accounts} from "../../../src/shared/ledger/accounts";
import {reasonEntryCannotPost} from "../../../src/shared/ledger/postJournalEntry";
import {
  expectedInDrawer,
  shiftVarianceJournalLines,
} from "../../../src/shared/ledger/shiftLines";

describe("what should be in a drawer", () => {
  it("is the float plus what came in", () => {
    expect(
      expectedInDrawer({
        openingFloat: 2000,
        cashCollected: 48500,
        cashRefunded: 0,
        receiptCount: 23,
      })
    ).toBe(50500);
  });

  it("takes refunds back out of the same money", () => {
    // A reckoning that ignored them would read short by exactly the
    // refunds, every time one happened.
    expect(
      expectedInDrawer({
        openingFloat: 2000,
        cashCollected: 48500,
        cashRefunded: 1500,
        receiptCount: 24,
      })
    ).toBe(49000);
  });

  it("rounds to centavos", () => {
    // Three shares of a fee leave a residue in binary floating point,
    // and a drawer expected to hold 50499.999999 is a drawer that is
    // always short.
    const third = 1000 / 3;
    expect(
      expectedInDrawer({
        openingFloat: 0,
        cashCollected: third * 3,
        cashRefunded: 0,
        receiptCount: 3,
      })
    ).toBe(1000);
  });

  it("holds its float when nothing was taken", () => {
    expect(
      expectedInDrawer({
        openingFloat: 2000,
        cashCollected: 0,
        cashRefunded: 0,
        receiptCount: 0,
      })
    ).toBe(2000);
  });
});

describe("the entry a difference makes", () => {
  it("posts nothing when the drawer balances", () => {
    // A pair of zero lines is a journal entry that says nothing, and an
    // entry of nothing is refused anyway.
    expect(shiftVarianceJournalLines(0)).toHaveLength(0);
    expect(shiftVarianceJournalLines(0.001)).toHaveLength(0);
  });

  it("takes a short drawer out of cash and charges the difference", () => {
    const lines = shiftVarianceJournalLines(-120);

    expect(reasonEntryCannotPost(lines)).toBeNull();
    expect(
      lines.find((l) => l.accountCode === Accounts.expenseCashVariance)?.debit
    ).toBe(120);
    expect(lines.find((l) => l.accountCode === Accounts.cashOnHand)?.credit).toBe(120);
  });

  it("puts an overage into cash, the same control failing the other way", () => {
    // Over is not good news. Both directions land in one account
    // somebody can look at.
    const lines = shiftVarianceJournalLines(5);

    expect(reasonEntryCannotPost(lines)).toBeNull();
    expect(lines.find((l) => l.accountCode === Accounts.cashOnHand)?.debit).toBe(5);
    expect(
      lines.find((l) => l.accountCode === Accounts.expenseCashVariance)?.credit
    ).toBe(5);
  });

  it("balances whichever way it falls, and at awkward amounts", () => {
    for (const variance of [-0.01, -1234.56, 0.05, 99999.99]) {
      const lines = shiftVarianceJournalLines(variance);
      expect(reasonEntryCannotPost(lines)).toBeNull();
    }
  });

  it("uses an account that is in the chart", () => {
    // A posting account that is not seeded is an entry that balances,
    // posts, and files the difference somewhere nobody can find.
    const lines = shiftVarianceJournalLines(-120);
    for (const line of lines) {
      expect(Object.values(Accounts)).toContain(line.accountCode);
    }
  });
});
