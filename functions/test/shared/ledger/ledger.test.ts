import * as fs from "fs";
import * as path from "path";
import {
  Accounts,
  STANDARD_CHART,
  cashAccountForMethod,
  revenueAccountForPurpose,
} from "../../../src/shared/ledger/accounts";
import {
  formatEntryNumber,
  reasonEntryCannotPost,
  sameMoney,
} from "../../../src/shared/ledger/postJournalEntry";
import {payrollJournalLines} from "../../../src/shared/ledger/payrollLines";

/** Sums both sides, the way the posting guard does. */
function balanced(lines: {debit?: number; credit?: number}[]): boolean {
  const debits = lines.reduce((s, l) => s + (l.debit ?? 0), 0);
  const credits = lines.reduce((s, l) => s + (l.credit ?? 0), 0);
  return sameMoney(debits, credits);
}

describe("an entry has to balance before it can post", () => {
  it("takes a balanced pair", () => {
    expect(
      reasonEntryCannotPost([
        {accountCode: Accounts.cashOnHand, debit: 1500},
        {accountCode: Accounts.receivableStudents, credit: 1500},
      ])
    ).toBeNull();
  });

  it("says by how much it is out", () => {
    // Shown to whoever tried. "Invalid entry" is not worth saying.
    const reason = reasonEntryCannotPost([
      {accountCode: Accounts.cashOnHand, debit: 1500},
      {accountCode: Accounts.revenueTuition, credit: 1000},
    ]);
    expect(reason).toContain("500.00");
  });

  it("refuses one line, no lines, and an entry of nothing", () => {
    expect(reasonEntryCannotPost([{accountCode: "1000", debit: 10}])).toContain(
      "at least two lines"
    );
    expect(reasonEntryCannotPost([])).toContain("at least two lines");
    expect(
      reasonEntryCannotPost([
        {accountCode: "1000", debit: 0, credit: 0},
        {accountCode: "4000", debit: 0, credit: 0},
      ])
    ).not.toBeNull();
  });

  it("refuses a line that is both sides, or negative", () => {
    expect(
      reasonEntryCannotPost([
        {accountCode: "1000", debit: 10, credit: 10},
        {accountCode: "4000", credit: 10},
      ])
    ).not.toBeNull();
    expect(
      reasonEntryCannotPost([
        {accountCode: "1000", debit: -10},
        {accountCode: "4000", credit: -10},
      ])
    ).toContain("cannot be negative");
  });

  it("refuses a line with no account", () => {
    expect(
      reasonEntryCannotPost([
        {accountCode: "   ", debit: 10},
        {accountCode: "4000", credit: 10},
      ])
    ).toContain("needs an account");
  });

  it("tolerates a residue of centavos", () => {
    // 0.1 + 0.2 is not 0.3 in binary floating point, and a journal is
    // exactly where that shows up. Three shares of a fee is the case a
    // school actually hits.
    const third = 1000 / 3;
    expect(
      reasonEntryCannotPost([
        {accountCode: Accounts.cashOnHand, debit: 1000},
        {accountCode: Accounts.revenueTuition, credit: third},
        {accountCode: Accounts.revenueMiscFees, credit: third},
        {accountCode: Accounts.revenueOther, credit: third},
      ])
    ).toBeNull();
  });

  it("does not tolerate a peso", () => {
    expect(
      reasonEntryCannotPost([
        {accountCode: Accounts.cashOnHand, debit: 1000},
        {accountCode: Accounts.revenueTuition, credit: 999},
      ])
    ).not.toBeNull();
  });
});

describe("entry numbers", () => {
  it("are padded and carry the year, so they sort and can be quoted", () => {
    expect(formatEntryNumber(42, 2026)).toBe("JE-2026-0042");
    expect(formatEntryNumber(1, 2026)).toBe("JE-2026-0001");
    // Past four digits it keeps counting rather than truncating.
    expect(formatEntryNumber(12345, 2026)).toBe("JE-2026-12345");
  });
});

describe("the chart of accounts", () => {
  it("has unique codes", () => {
    const codes = STANDARD_CHART.map((a) => a.code);
    expect(new Set(codes).size).toBe(codes.length);
  });

  it("puts every account in the block its type owns", () => {
    // Assets in the 1000s, liabilities in the 2000s. An expense filed
    // under 1500 lands on the balance sheet as an asset.
    const block: Record<string, string> = {
      asset: "1", liability: "2", equity: "3", revenue: "4", expense: "5",
    };
    for (const account of STANDARD_CHART) {
      expect(account.code.startsWith(block[account.type])).toBe(true);
    }
  });

  it("seeds every account the postings reference", () => {
    const codes = new Set(STANDARD_CHART.map((a) => a.code));
    for (const code of Object.values(Accounts)) {
      expect(codes.has(code)).toBe(true);
    }
  });

  it("has not drifted from the copy the app reads", () => {
    // Two copies because the posting happens here, inside the
    // transaction that writes the payment, and the reading happens in
    // the app -- neither can import the other. This is the test that
    // keeps them the same file in two languages.
    const dartPath = path.resolve(
      __dirname,
      "../../../../app/lib/features/ledger/domain/entities/ledger_account.dart"
    );
    const dart = fs.readFileSync(dartPath, "utf8");

    const dartCodes = new Map<string, string>();
    for (const match of dart.matchAll(/static const (\w+) = '(\d{4})';/g)) {
      dartCodes.set(match[1], match[2]);
    }

    expect(dartCodes.size).toBeGreaterThan(10);
    for (const [name, code] of Object.entries(Accounts)) {
      expect(dartCodes.get(name)).toBe(code);
    }
    expect(dartCodes.size).toBe(Object.keys(Accounts).length);
  });
});

describe("where money lands", () => {
  it("sends each method to the cash account it really sits in", () => {
    expect(cashAccountForMethod("cash")).toBe(Accounts.cashOnHand);
    expect(cashAccountForMethod("gcash")).toBe(Accounts.eWallet);
    expect(cashAccountForMethod("bank_transfer")).toBe(Accounts.cashInBank);
    expect(cashAccountForMethod("online")).toBe(Accounts.cashInBank);
  });

  it("does not take a payment down over a method it has not heard of", () => {
    expect(cashAccountForMethod("crypto")).toBe(Accounts.cashOnHand);
    expect(revenueAccountForPurpose("nonsense")).toBe(Accounts.revenueOther);
  });
});

describe("the payroll entry", () => {
  /** One payslip with contributions, as buildPayslip produces. */
  const withContributions = {
    grossPay: 20000,
    netPay: 17000,
    totalDeductions: 3000,
    employerContributions: 1500,
    employerByKind: {sss: 1000, philhealth: 300, pagibig: 200},
    deductions: [
      {amount: 900, kind: "sss"},
      {amount: 300, kind: "philhealth"},
      {amount: 200, kind: "pagibig"},
      {amount: 1600, kind: "withholding_tax"},
    ],
  };

  it("balances", () => {
    const lines = payrollJournalLines([withContributions]);
    expect(balanced(lines)).toBe(true);
    expect(reasonEntryCannotPost(lines)).toBeNull();
  });

  it("charges the employer share to benefits, not to salaries", () => {
    // Miss it and the entry still balances -- it just understates both
    // the expense and the liability, and nobody notices until a
    // remittance is short.
    const lines = payrollJournalLines([withContributions]);
    const benefits = lines.find((l) => l.accountCode === Accounts.expenseBenefits);
    expect(benefits?.debit).toBe(1500);

    const salaries = lines.find((l) => l.accountCode === Accounts.expenseSalaries);
    expect(salaries?.debit).toBe(20000);
  });

  it("credits each agency its own payable, both halves together", () => {
    // One payment per agency is how it is remitted, so one line per
    // agency is how it is owed.
    const lines = payrollJournalLines([withContributions]);
    const credited = (code: string) =>
      lines.filter((l) => l.accountCode === code).reduce((s, l) => s + (l.credit ?? 0), 0);

    expect(credited(Accounts.payableSss)).toBe(1900); // 900 withheld + 1000 employer
    expect(credited(Accounts.payablePhilHealth)).toBe(600);
    expect(credited(Accounts.payablePagIbig)).toBe(400);
    expect(credited(Accounts.payableWithholding)).toBe(1600);
    expect(credited(Accounts.cashInBank)).toBe(17000);
  });

  it("treats an absence as pay never owed, not as something withheld", () => {
    // It never became a liability to anybody. It reduces what is charged
    // to salaries instead, and the entry still has to balance.
    const withAbsence = {
      grossPay: 20000,
      netPay: 18500,
      totalDeductions: 1500,
      employerContributions: 0,
      employerByKind: {},
      deductions: [{amount: 1500, kind: null}],
    };
    const lines = payrollJournalLines([withAbsence]);

    expect(balanced(lines)).toBe(true);
    const salaries = lines.find((l) => l.accountCode === Accounts.expenseSalaries);
    expect(salaries?.debit).toBe(18500);
    expect(lines.some((l) => l.accountCode === Accounts.payableSss)).toBe(false);
  });

  it("balances a run with no deductions at all", () => {
    // A school that has not confirmed its contribution tables issues
    // payslips with nothing withheld. Gross is net, and the entry is two
    // lines.
    const lines = payrollJournalLines([
      {
        grossPay: 15000,
        netPay: 15000,
        totalDeductions: 0,
        employerContributions: 0,
        deductions: [],
      },
    ]);

    expect(balanced(lines)).toBe(true);
    expect(lines).toHaveLength(2);
  });

  it("adds a whole staff up, and still balances", () => {
    const lines = payrollJournalLines([
      withContributions,
      withContributions,
      {
        grossPay: 13333.33,
        netPay: 11333.33,
        totalDeductions: 2000,
        employerContributions: 666.67,
        employerByKind: {sss: 666.67},
        deductions: [{amount: 2000, kind: "sss"}],
      },
    ]);

    expect(balanced(lines)).toBe(true);
    expect(reasonEntryCannotPost(lines)).toBeNull();
  });

  it("puts a contribution kind it does not know somewhere real", () => {
    // Rather than dropping the line and unbalancing the entry.
    const lines = payrollJournalLines([
      {
        grossPay: 10000,
        netPay: 9000,
        totalDeductions: 1000,
        employerContributions: 0,
        deductions: [{amount: 1000, kind: "provident_fund"}],
      },
    ]);

    expect(balanced(lines)).toBe(true);
    expect(lines.some((l) => l.accountCode === Accounts.payableTrade)).toBe(true);
  });

  it("reads the same way every run", () => {
    // Somebody is comparing this month's voucher against last month's.
    const first = payrollJournalLines([withContributions]).map((l) => l.accountCode);
    const second = payrollJournalLines([withContributions]).map((l) => l.accountCode);
    expect(first).toEqual(second);
  });
});
