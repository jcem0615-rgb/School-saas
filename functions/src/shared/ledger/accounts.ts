/**
 * The chart of accounts, server side.
 *
 * The twin of app/lib/features/ledger/domain/entities/ledger_account.dart.
 * Two copies because the posting happens here -- inside the transaction
 * that writes the payment -- and the reading happens there, and neither
 * can import the other. The test in test/shared/ledger/accounts.test.ts
 * checks the codes have not drifted apart.
 */

export type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";

export interface LedgerAccountSeed {
  code: string;
  name: string;
  type: AccountType;
  isSystem: boolean;
  description?: string;
}

/**
 * The codes the automatic postings use.
 *
 * Constants rather than strings scattered through the callables: a typo
 * in a posting account is a journal entry that balances, posts, and
 * quietly files the school's tuition under Utilities.
 */
export const Accounts = {
  cashOnHand: "1000",
  cashInBank: "1010",
  eWallet: "1020",
  receivableStudents: "1200",

  payableTrade: "2000",
  payableSss: "2100",
  payablePhilHealth: "2110",
  payablePagIbig: "2120",
  payableWithholding: "2130",

  fundBalance: "3000",

  revenueTuition: "4000",
  revenueMiscFees: "4010",
  revenueOther: "4090",

  expenseSalaries: "5000",
  expenseBenefits: "5010",
  expenseUtilities: "5100",
  expenseSupplies: "5200",
  expenseRepairs: "5300",
  expenseCashVariance: "5910",
  expenseOther: "5900",
} as const;

export const STANDARD_CHART: LedgerAccountSeed[] = [
  {code: Accounts.cashOnHand, name: "Cash on Hand", type: "asset", isSystem: true,
    description: "Money at the cashier window, before it is deposited."},
  {code: Accounts.cashInBank, name: "Cash in Bank", type: "asset", isSystem: true,
    description: "Bank transfers and deposits."},
  {code: Accounts.eWallet, name: "E-Wallet", type: "asset", isSystem: true,
    description: "GCash and other online collections."},
  {code: Accounts.receivableStudents, name: "Accounts Receivable - Students",
    type: "asset", isSystem: true,
    description: "Assessed fees not yet collected. Moves with the balance on the student record."},

  {code: Accounts.payableTrade, name: "Accounts Payable", type: "liability", isSystem: true,
    description: "Bills received and not yet paid."},
  {code: Accounts.payableSss, name: "SSS Payable", type: "liability", isSystem: true,
    description: "Withheld from payroll, owed to SSS."},
  {code: Accounts.payablePhilHealth, name: "PhilHealth Payable", type: "liability", isSystem: true},
  {code: Accounts.payablePagIbig, name: "Pag-IBIG Payable", type: "liability", isSystem: true},
  {code: Accounts.payableWithholding, name: "Withholding Tax Payable",
    type: "liability", isSystem: true,
    description: "Withheld from payroll, owed to the BIR."},

  {code: Accounts.fundBalance, name: "Fund Balance", type: "equity", isSystem: true,
    description: "What the school is worth once what it owes is taken off."},

  {code: Accounts.revenueTuition, name: "Tuition Revenue", type: "revenue", isSystem: true},
  {code: Accounts.revenueMiscFees, name: "Miscellaneous Fees", type: "revenue", isSystem: true},
  {code: Accounts.revenueOther, name: "Other Income", type: "revenue", isSystem: true},

  {code: Accounts.expenseSalaries, name: "Salaries and Wages", type: "expense", isSystem: true},
  {code: Accounts.expenseBenefits, name: "Employee Benefits", type: "expense", isSystem: true,
    description: "The school's own share of SSS, PhilHealth and Pag-IBIG."},
  {code: Accounts.expenseUtilities, name: "Utilities", type: "expense", isSystem: false},
  {code: Accounts.expenseSupplies, name: "Supplies", type: "expense", isSystem: false},
  {code: Accounts.expenseRepairs, name: "Repairs and Maintenance", type: "expense", isSystem: false},
  {code: Accounts.expenseCashVariance, name: "Cash Short or Over",
    type: "expense", isSystem: true,
    description: "Where a counted drawer differs from what it should hold. " +
      "A credit balance here means the drawers have run over."},
  {code: Accounts.expenseOther, name: "Other Expenses", type: "expense", isSystem: true},
];

/** Names for the denormalised accountName on each line. */
export const ACCOUNT_NAMES: Record<string, string> = Object.fromEntries(
  STANDARD_CHART.map((a) => [a.code, a.name])
);

/**
 * Which cash account a payment method lands in.
 *
 * An online payment is a bank deposit by the time the school sees it;
 * GCash sits in the wallet until it is cashed out. Getting this wrong
 * makes a bank reconciliation impossible, which is the one thing the
 * accounting office checks first.
 */
export function cashAccountForMethod(method: string): string {
  switch (method) {
  case "cash": return Accounts.cashOnHand;
  case "gcash": return Accounts.eWallet;
  case "bank_transfer": return Accounts.cashInBank;
  case "online": return Accounts.cashInBank;
  // A method this build has not heard of must not take the payment down
  // with it. It lands somewhere real and visible.
  default: return Accounts.cashOnHand;
  }
}

export function revenueAccountForPurpose(purpose: string): string {
  switch (purpose) {
  case "tuition": return Accounts.revenueTuition;
  case "misc_fee": return Accounts.revenueMiscFees;
  default: return Accounts.revenueOther;
  }
}
