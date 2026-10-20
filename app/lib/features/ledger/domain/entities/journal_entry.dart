import 'ledger_account.dart';

/// Where an entry came from.
///
/// Almost nothing in this ledger is typed by a person. A school that
/// hand-keys its tuition into the books ends up with two truths -- the
/// payments the cashier recorded, and the journal somebody wrote up
/// afterwards -- and reconciling them is the week this product exists to
/// give back. So the source is on every entry, and [manual] is the
/// exception rather than the rule.
enum EntrySource {
  payment('payment', 'Payment'),
  refund('refund', 'Refund'),
  assessment('assessment', 'Fee assessment'),
  payroll('payroll', 'Payroll'),
  expense('expense', 'Expense'),
  bill('bill', 'Supplier bill'),
  billPayment('bill_payment', 'Bill payment'),
  manual('manual', 'Manual entry'),
  reversal('reversal', 'Reversal');

  final String value;
  final String displayLabel;
  const EntrySource(this.value, this.displayLabel);

  static EntrySource fromString(String value) => EntrySource.values
      .firstWhere((s) => s.value == value, orElse: () => EntrySource.manual);

  /// Whether a person may post this kind of entry by hand.
  ///
  /// Everything else is written by the thing that caused it, inside the
  /// same transaction, so the books cannot disagree with the receipt.
  bool get isHandWritten => this == EntrySource.manual || this == EntrySource.reversal;
}

/// One side of one entry.
///
/// A line is a debit or a credit, never both and never neither. Storing
/// both as nullable numbers and letting one be zero is how you end up
/// with a line that means nothing and a total that still balances.
class JournalLine {
  final String accountCode;

  /// The account name as it stood when the entry was posted.
  ///
  /// Denormalised deliberately, like `DocumentRelease.studentName`: a
  /// school that renames 5100 from "Utilities" to "Light and Water"
  /// should not have last year's vouchers silently re-captioned.
  final String accountName;

  final double debit;
  final double credit;
  final String? memo;

  const JournalLine({
    required this.accountCode,
    required this.accountName,
    this.debit = 0,
    this.credit = 0,
    this.memo,
  });

  JournalLine.debit(
    this.accountCode,
    this.accountName,
    double amount, {
    this.memo,
  })  : debit = amount,
        credit = 0;

  JournalLine.credit(
    this.accountCode,
    this.accountName,
    double amount, {
    this.memo,
  })  : debit = 0,
        credit = amount;

  bool get isDebit => debit > 0;
  double get amount => isDebit ? debit : credit;

  /// A line has to be one side or the other, and positive.
  bool get isWellFormed =>
      accountCode.trim().isNotEmpty &&
      debit >= 0 &&
      credit >= 0 &&
      (debit > 0) != (credit > 0);
}

/// One journal entry: the thing that is posted, in full, or not at all.
///
/// Immutable once written. A mistake is corrected by posting the reverse
/// of it, which is what an accounting office does with a paper journal
/// and for the same reason -- the correction is itself a record, and a
/// book you can go back and tidy is a book nobody can rely on. See
/// firestore.rules: no update rule, no delete rule, for anyone.
class JournalEntry {
  final String id;

  /// The sequential number on the voucher. What gets quoted in an audit.
  final String entryNumber;

  /// The day the money moved, which is not always the day it was typed.
  final DateTime date;

  final String memo;
  final EntrySource source;

  /// The payment, payslip, bill or expense this came from. Null only for
  /// a manual entry, which is the one kind with nothing behind it.
  final String? sourceId;

  final List<JournalLine> lines;

  final String postedByName;
  final DateTime postedAt;

  /// Set on an entry that reverses another, and on the one reversed.
  final String? reversalOf;
  final String? reversedBy;

  const JournalEntry({
    required this.id,
    required this.entryNumber,
    required this.date,
    required this.memo,
    required this.source,
    required this.lines,
    required this.postedByName,
    required this.postedAt,
    this.sourceId,
    this.reversalOf,
    this.reversedBy,
  });

  double get totalDebits =>
      lines.fold(0, (sum, l) => sum + l.debit);
  double get totalCredits =>
      lines.fold(0, (sum, l) => sum + l.credit);

  /// What the entry is worth, for a list that shows one figure.
  double get amount => totalDebits;

  bool get isReversed => reversedBy != null;
  bool get isReversal => reversalOf != null;

  /// The reverse of this entry, ready to post.
  ///
  /// Every debit becomes a credit and back again. The memo says what it
  /// undoes, because an entry that reads "Reversal" and nothing else
  /// leaves the next person to work out which one.
  List<JournalLine> reversedLines() => [
        for (final l in lines)
          JournalLine(
            accountCode: l.accountCode,
            accountName: l.accountName,
            debit: l.credit,
            credit: l.debit,
            memo: l.memo,
          ),
      ];
}

/// Money is counted in centavos, and a double is not.
///
/// 0.1 + 0.2 is not 0.3 in binary floating point, and a trial balance is
/// exactly the place that shows up: twelve postings of ₱333.33 against
/// one of ₱999.99 leaves a residue of a few billionths, and a strict
/// equality check then reports the books as out of balance for ever.
/// Everything here compares to the nearest centavo instead.
const centavo = 0.005;

bool sameMoney(double a, double b) => (a - b).abs() < centavo;

/// Whether a set of lines may be posted.
///
/// Returns the reason it may not, or null when it may -- a string rather
/// than a bool because every one of these is shown to the person who
/// tried, and "this entry is invalid" is not worth saying.
String? reasonEntryCannotPost(List<JournalLine> lines) {
  if (lines.length < 2) {
    return 'An entry needs at least two lines: what was given and what was got.';
  }
  if (lines.any((l) => !l.isWellFormed)) {
    return 'Every line has to be a debit or a credit, and more than zero.';
  }
  final debits = lines.fold<double>(0, (sum, l) => sum + l.debit);
  final credits = lines.fold<double>(0, (sum, l) => sum + l.credit);
  if (!sameMoney(debits, credits)) {
    final difference = (debits - credits).abs().toStringAsFixed(2);
    return 'Debits and credits differ by $difference. An entry has to balance.';
  }
  if (debits <= 0) {
    return 'An entry of nothing is not an entry.';
  }
  return null;
}

/// What one account is worth, once every entry touching it is counted.
class AccountBalance {
  final LedgerAccount account;
  final double debits;
  final double credits;

  const AccountBalance({
    required this.account,
    required this.debits,
    required this.credits,
  });

  /// Positive in the direction the account normally runs.
  ///
  /// A bookkeeper reading "Cash on Hand: 48,200" expects that to mean the
  /// school has it, not that the debits happened to exceed the credits by
  /// that much -- which is the same number and a worse sentence.
  double get balance => account.type.increasesOnDebit
      ? debits - credits
      : credits - debits;

  bool get isEmpty => sameMoney(debits, 0) && sameMoney(credits, 0);
}

/// The trial balance: every account, and the proof that the books add up.
class TrialBalance {
  final List<AccountBalance> rows;
  final DateTime asOf;

  const TrialBalance({required this.rows, required this.asOf});

  /// Builds one from the chart and the entries posted against it.
  ///
  /// Entries naming an account that is not in the chart are not dropped:
  /// they are the ones that matter, because an account disappearing from
  /// the chart while entries still cite it is how a trial balance stops
  /// balancing and nobody can see why. They come back under a placeholder
  /// so the total is still right and the problem is visible.
  factory TrialBalance.from({
    required Iterable<LedgerAccount> chart,
    required Iterable<JournalEntry> entries,
    DateTime? asOf,
  }) {
    final byCode = {for (final a in chart) a.code: a};
    final debits = <String, double>{};
    final credits = <String, double>{};

    for (final entry in entries) {
      for (final line in entry.lines) {
        debits[line.accountCode] = (debits[line.accountCode] ?? 0) + line.debit;
        credits[line.accountCode] = (credits[line.accountCode] ?? 0) + line.credit;
      }
    }

    final codes = {...byCode.keys, ...debits.keys, ...credits.keys}.toList()..sort();
    final rows = <AccountBalance>[];
    for (final code in codes) {
      final account = byCode[code] ??
          LedgerAccount(
            code: code,
            name: 'Unknown account',
            type: AccountType.expense,
            isActive: false,
            description: 'Entries cite this code but the chart has no such '
                'account. Nothing is lost -- it is shown here so it can be '
                'put right.',
          );
      rows.add(AccountBalance(
        account: account,
        debits: debits[code] ?? 0,
        credits: credits[code] ?? 0,
      ));
    }

    rows.sort((a, b) {
      final byType = a.account.type.sortOrder.compareTo(b.account.type.sortOrder);
      return byType != 0 ? byType : a.account.code.compareTo(b.account.code);
    });

    return TrialBalance(rows: rows, asOf: asOf ?? DateTime.now());
  }

  double get totalDebits => rows.fold(0, (sum, r) => sum + r.debits);
  double get totalCredits => rows.fold(0, (sum, r) => sum + r.credits);

  /// The one line an accountant looks at first.
  bool get balances => sameMoney(totalDebits, totalCredits);

  /// Rows worth showing: an account nothing has ever posted to is noise
  /// on a trial balance, and a school's chart always has a few.
  List<AccountBalance> get posted => rows.where((r) => !r.isEmpty).toList();

  double totalFor(AccountType type) => rows
      .where((r) => r.account.type == type)
      .fold<double>(0, (sum, r) => sum + r.balance);

  /// Revenue less expenses: what the school made this period.
  double get surplus =>
      totalFor(AccountType.revenue) - totalFor(AccountType.expense);
}
