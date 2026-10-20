/// The chart of accounts: the short list of buckets every peso lands in.
///
/// A school's accounting office already has one, usually on the first
/// page of a ledger book. The codes are theirs by convention -- assets in
/// the 1000s, liabilities in the 2000s -- and a system that invented its
/// own numbering would be the first thing a bookkeeper refused to use.
library;

/// What kind of thing an account counts, and therefore which side of an
/// entry increases it.
///
/// This is the whole of double-entry bookkeeping that has to be encoded:
/// everything else follows from it. An asset goes up on the debit side, a
/// revenue goes up on the credit side, and a system that gets this wrong
/// produces a trial balance that balances and means nothing.
enum AccountType {
  asset('asset', 'Assets', true),
  liability('liability', 'Liabilities', false),
  equity('equity', 'Equity', false),
  revenue('revenue', 'Revenue', false),
  expense('expense', 'Expenses', true);

  final String value;
  final String groupLabel;

  /// True when a debit increases this account.
  final bool increasesOnDebit;

  const AccountType(this.value, this.groupLabel, this.increasesOnDebit);

  static AccountType fromString(String value) => AccountType.values
      .firstWhere((t) => t.value == value, orElse: () => AccountType.expense);

  /// Which side the account normally sits on, for display.
  String get normalBalance => increasesOnDebit ? 'Debit' : 'Credit';

  /// Assets and expenses are what the school has and what it spent;
  /// everything else is where the money came from. Used to order the
  /// chart the way a bookkeeper expects to read it.
  int get sortOrder => switch (this) {
        AccountType.asset => 0,
        AccountType.liability => 1,
        AccountType.equity => 2,
        AccountType.revenue => 3,
        AccountType.expense => 4,
      };
}

class LedgerAccount {
  /// The number a bookkeeper quotes: "charge it to 5100".
  final String code;
  final String name;
  final AccountType type;

  /// Seeded accounts that the automatic postings reference by code.
  ///
  /// They can be renamed -- a school that calls 4010 "Other School Fees"
  /// should see that everywhere -- but not deactivated and not
  /// renumbered, because a payment posted next week has to find them.
  final bool isSystem;

  final bool isActive;
  final String? description;

  const LedgerAccount({
    required this.code,
    required this.name,
    required this.type,
    this.isSystem = false,
    this.isActive = true,
    this.description,
  });

  /// "5100 - Utilities", which is how it reads on a voucher.
  String get label => '$code - $name';

  LedgerAccount copyWith({String? name, bool? isActive, String? description}) =>
      LedgerAccount(
        code: code,
        name: name ?? this.name,
        type: type,
        isSystem: isSystem,
        isActive: isActive ?? this.isActive,
        description: description ?? this.description,
      );
}

/// The codes the automatic postings use.
///
/// Constants rather than strings scattered through the callables: a typo
/// in a posting account is a journal entry that balances, posts, and
/// quietly files the school's tuition under Utilities.
abstract final class Accounts {
  static const cashOnHand = '1000';
  static const cashInBank = '1010';
  static const eWallet = '1020';
  static const receivableStudents = '1200';

  static const payableTrade = '2000';
  static const payableSss = '2100';
  static const payablePhilHealth = '2110';
  static const payablePagIbig = '2120';
  static const payableWithholding = '2130';

  static const fundBalance = '3000';

  static const revenueTuition = '4000';
  static const revenueMiscFees = '4010';
  static const revenueOther = '4090';

  static const expenseSalaries = '5000';
  static const expenseBenefits = '5010';
  static const expenseUtilities = '5100';
  static const expenseSupplies = '5200';
  static const expenseRepairs = '5300';
  static const expenseOther = '5900';
}

/// What a school starts with on day one.
///
/// Small on purpose. A chart with two hundred accounts is one nobody
/// codes against correctly, and a school that needs more can add them --
/// what it cannot do is work out which of two hundred it was supposed to
/// use. These are the ones the product itself posts to, plus the handful
/// every school spends money on.
const standardChartOfAccounts = <LedgerAccount>[
  LedgerAccount(
    code: Accounts.cashOnHand,
    name: 'Cash on Hand',
    type: AccountType.asset,
    isSystem: true,
    description: 'Money at the cashier window, before it is deposited.',
  ),
  LedgerAccount(
    code: Accounts.cashInBank,
    name: 'Cash in Bank',
    type: AccountType.asset,
    isSystem: true,
    description: 'Bank transfers and deposits.',
  ),
  LedgerAccount(
    code: Accounts.eWallet,
    name: 'E-Wallet',
    type: AccountType.asset,
    isSystem: true,
    description: 'GCash and other online collections.',
  ),
  LedgerAccount(
    code: Accounts.receivableStudents,
    name: 'Accounts Receivable - Students',
    type: AccountType.asset,
    isSystem: true,
    description: 'Assessed fees not yet collected. Moves with the balance '
        'on the student record.',
  ),
  LedgerAccount(
    code: Accounts.payableTrade,
    name: 'Accounts Payable',
    type: AccountType.liability,
    isSystem: true,
    description: 'Bills received and not yet paid.',
  ),
  LedgerAccount(
    code: Accounts.payableSss,
    name: 'SSS Payable',
    type: AccountType.liability,
    isSystem: true,
    description: 'Withheld from payroll, owed to SSS.',
  ),
  LedgerAccount(
    code: Accounts.payablePhilHealth,
    name: 'PhilHealth Payable',
    type: AccountType.liability,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.payablePagIbig,
    name: 'Pag-IBIG Payable',
    type: AccountType.liability,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.payableWithholding,
    name: 'Withholding Tax Payable',
    type: AccountType.liability,
    isSystem: true,
    description: 'Withheld from payroll, owed to the BIR.',
  ),
  LedgerAccount(
    code: Accounts.fundBalance,
    name: 'Fund Balance',
    type: AccountType.equity,
    isSystem: true,
    description: 'What the school is worth once what it owes is taken off.',
  ),
  LedgerAccount(
    code: Accounts.revenueTuition,
    name: 'Tuition Revenue',
    type: AccountType.revenue,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.revenueMiscFees,
    name: 'Miscellaneous Fees',
    type: AccountType.revenue,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.revenueOther,
    name: 'Other Income',
    type: AccountType.revenue,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.expenseSalaries,
    name: 'Salaries and Wages',
    type: AccountType.expense,
    isSystem: true,
  ),
  LedgerAccount(
    code: Accounts.expenseBenefits,
    name: 'Employee Benefits',
    type: AccountType.expense,
    isSystem: true,
    description: "The school's own share of SSS, PhilHealth and Pag-IBIG.",
  ),
  LedgerAccount(code: Accounts.expenseUtilities, name: 'Utilities', type: AccountType.expense),
  LedgerAccount(code: Accounts.expenseSupplies, name: 'Supplies', type: AccountType.expense),
  LedgerAccount(
    code: Accounts.expenseRepairs,
    name: 'Repairs and Maintenance',
    type: AccountType.expense,
  ),
  LedgerAccount(
    code: Accounts.expenseOther,
    name: 'Other Expenses',
    type: AccountType.expense,
    isSystem: true,
  ),
];

/// Which cash account a payment method lands in.
///
/// An online payment is a bank deposit by the time the school sees it;
/// GCash sits in the wallet until it is cashed out. Getting this wrong
/// makes a bank reconciliation impossible, which is the one thing the
/// accounting office will check first.
String cashAccountForMethod(String method) => switch (method) {
      'cash' => Accounts.cashOnHand,
      'gcash' => Accounts.eWallet,
      'bank_transfer' => Accounts.cashInBank,
      'online' => Accounts.cashInBank,
      _ => Accounts.cashOnHand,
    };

/// Which revenue account a fee is earned into.
String revenueAccountForPurpose(String purpose) => switch (purpose) {
      'tuition' => Accounts.revenueTuition,
      'misc_fee' => Accounts.revenueMiscFees,
      _ => Accounts.revenueOther,
    };
