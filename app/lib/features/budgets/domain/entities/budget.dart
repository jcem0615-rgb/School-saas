/// What the school meant to spend, next to what it did.
///
/// A budget is a plan, and that is the whole of what makes this module
/// different from the three around it. The ledger, the payables ledger
/// and the collections are records of things that happened; a budget is
/// a statement of intent, and intent is allowed to be wrong.
///
/// It follows that **a budget never refuses anything**. A school that
/// cannot record the electricity bill because somebody budgeted too
/// little does not thereby spend less -- it just has a liability nobody
/// can see, which is worse than an overspend somebody can. So every
/// breach here is a warning, shown where the money is being committed,
/// and never a block.
library;

import '../../../ledger/domain/entities/journal_entry.dart'
    show AccountBalance, TrialBalance, centavo, sameMoney;
import '../../../ledger/domain/entities/ledger_account.dart';

/// One account's allowance for one school year.
///
/// Keyed by the pair, so a school cannot end up with two budgets for the
/// same account and no way to tell which one anybody meant.
class Budget {
  /// "2026-2027".
  final String schoolYear;
  final String accountCode;

  /// The account name as it stood when the budget was set, for the same
  /// reason every other name in this system is denormalised.
  final String accountName;

  final double amount;
  final String? note;
  final String setByName;
  final DateTime setAt;

  const Budget({
    required this.schoolYear,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    required this.setByName,
    required this.setAt,
    this.note,
  });

  /// The document id: one budget per account per year, by construction.
  String get id => '${schoolYear}_$accountCode';

  Budget copyWith({double? amount, String? note}) => Budget(
        schoolYear: schoolYear,
        accountCode: accountCode,
        accountName: accountName,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        setByName: setByName,
        setAt: setAt,
      );
}

/// How a line is doing against its allowance.
enum BudgetState {
  /// Comfortably inside it.
  within('Within budget'),

  /// Four fifths gone. Early enough to do something about it, which is
  /// the only point at which a warning is worth anything.
  near('Running low'),

  /// Spent more than was set aside.
  over('Over budget'),

  /// Money spent on an account nobody budgeted for.
  ///
  /// The mirror of an entry citing an account the chart has lost: a
  /// budget report that quietly omitted this would be a report that
  /// balances and hides the thing it exists to find.
  unbudgeted('Not budgeted');

  final String displayLabel;
  const BudgetState(this.displayLabel);
}

/// Where this line stops being comfortable. Four fifths, which leaves a
/// term's notice on a year's budget.
const nearLimitFraction = 0.8;

/// One row of the budget report.
class BudgetLine {
  final String accountCode;
  final String accountName;
  final AccountType accountType;

  /// Zero when nothing was budgeted for this account.
  final double budgeted;

  /// What the books say was actually spent, or earned.
  final double actual;

  final String? note;

  const BudgetLine({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.budgeted,
    required this.actual,
    this.note,
  });

  bool get isBudgeted => budgeted > 0;

  /// What is left. Negative when overspent, and deliberately so: a
  /// report that clamped this at zero would hide how far over.
  double get remaining => budgeted - actual;

  /// How much of the allowance is gone, as a fraction.
  ///
  /// Null when nothing was budgeted -- a percentage of zero is either
  /// infinity or nonsense, and both read badly on a screen.
  double? get usedFraction => isBudgeted ? actual / budgeted : null;

  BudgetState get state {
    if (!isBudgeted) {
      // Nothing budgeted and nothing spent is not a line worth a state;
      // the report drops those. Anything spent is unbudgeted.
      return sameMoney(actual, 0) ? BudgetState.within : BudgetState.unbudgeted;
    }
    if (actual - budgeted > centavo) return BudgetState.over;
    if (actual >= budgeted * nearLimitFraction) return BudgetState.near;
    return BudgetState.within;
  }

  /// Whether spending [more] on this account would take it past its
  /// allowance.
  ///
  /// Asked before a bill is recorded, and answered with a warning rather
  /// than a refusal. See the note at the top of this file.
  bool wouldBreachWith(double more) =>
      isBudgeted && (actual + more) - budgeted > centavo;
}

/// The budget report: every line that has a budget or a spend.
class BudgetReport {
  final String schoolYear;
  final List<BudgetLine> lines;

  const BudgetReport({required this.schoolYear, required this.lines});

  /// Builds the report from the budgets and the books.
  ///
  /// The actuals come from the trial balance rather than from a running
  /// total kept somewhere: a stored "spent so far" is a second truth,
  /// and it drifts the first time something posts without updating it.
  /// The books already know, so the books are asked.
  factory BudgetReport.from({
    required String schoolYear,
    required Iterable<Budget> budgets,
    required TrialBalance books,
  }) {
    final byCode = {for (final b in budgets) b.accountCode: b};
    final balances = <String, AccountBalance>{
      for (final row in books.rows) row.account.code: row,
    };

    final codes = {...byCode.keys, ...balances.keys};
    final lines = <BudgetLine>[];

    for (final code in codes) {
      final budget = byCode[code];
      final balance = balances[code];
      final account = balance?.account;

      // Only spending and earning are budgeted. A school does not budget
      // its bank balance, and a report that listed Cash on Hand next to
      // Utilities would be one nobody reads twice.
      final type = account?.type ??
          (code.startsWith('4') ? AccountType.revenue : AccountType.expense);
      if (type != AccountType.expense && type != AccountType.revenue) continue;

      final budgeted = budget?.amount ?? 0;
      final actual = balance?.balance ?? 0;
      // Nothing set aside and nothing spent: not a row, just an account
      // that had a quiet year.
      if (budgeted <= 0 && sameMoney(actual, 0)) continue;

      lines.add(BudgetLine(
        accountCode: code,
        accountName: budget?.accountName ?? account?.name ?? 'Unknown account',
        accountType: type,
        budgeted: budgeted,
        actual: actual,
        note: budget?.note,
      ));
    }

    lines.sort((a, b) {
      final byType = a.accountType.sortOrder.compareTo(b.accountType.sortOrder);
      return byType != 0 ? byType : a.accountCode.compareTo(b.accountCode);
    });

    return BudgetReport(schoolYear: schoolYear, lines: lines);
  }

  List<BudgetLine> forType(AccountType type) =>
      lines.where((l) => l.accountType == type).toList();

  double budgetedFor(AccountType type) =>
      forType(type).fold(0, (sum, l) => sum + l.budgeted);

  double actualFor(AccountType type) =>
      forType(type).fold(0, (sum, l) => sum + l.actual);

  /// The lines somebody needs to look at, worst first.
  ///
  /// Over budget before running low, and within each group the biggest
  /// overspend first -- a report that listed them by account code would
  /// make somebody read all of it to find the one that matters.
  List<BudgetLine> get needingAttention {
    final flagged = lines
        .where((l) =>
            l.state == BudgetState.over || l.state == BudgetState.unbudgeted ||
            l.state == BudgetState.near)
        .toList();
    flagged.sort((a, b) {
      int rank(BudgetLine l) => switch (l.state) {
            BudgetState.over => 0,
            BudgetState.unbudgeted => 1,
            BudgetState.near => 2,
            BudgetState.within => 3,
          };
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (b.actual - b.budgeted).compareTo(a.actual - a.budgeted);
    });
    return flagged;
  }

  /// The line for one account, or null when it is neither budgeted nor
  /// spent on.
  BudgetLine? lineFor(String accountCode) =>
      lines.where((l) => l.accountCode == accountCode).firstOrNull;

  bool get isEmpty => lines.isEmpty;

  /// What the school planned to be left with: budgeted revenue less
  /// budgeted spending.
  double get plannedSurplus =>
      budgetedFor(AccountType.revenue) - budgetedFor(AccountType.expense);

  /// And what it is actually left with so far.
  double get actualSurplus =>
      actualFor(AccountType.revenue) - actualFor(AccountType.expense);
}

/// Why a budget cannot be set, or null.
String? reasonBudgetCannotBeSet({
  required String schoolYear,
  required LedgerAccount? account,
  required double amount,
}) {
  if (schoolYear.trim().isEmpty) return 'Choose a school year.';
  if (account == null) return 'Choose an account to budget.';
  // Budgeting a bank balance is a category error, and the report would
  // not know what to do with it.
  if (account.type != AccountType.expense && account.type != AccountType.revenue) {
    return 'Only spending and income are budgeted. '
        '${account.label} is ${account.type.groupLabel.toLowerCase()}.';
  }
  if (amount < 0) return 'A budget cannot be a negative amount.';
  if (!amount.isFinite) return 'That is not an amount.';
  return null;
}
