import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/budgets/domain/entities/budget.dart';
import 'package:logicclass/features/ledger/domain/entities/journal_entry.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';

/// A budget is a plan, and a plan is allowed to be wrong.
///
/// Most of these tests are about a breach being *visible* rather than
/// being prevented -- and about the two things a budget report must not
/// do: hide money spent on an account nobody budgeted, and clamp an
/// overspend so nobody can see how far over it went.
void main() {
  Budget budget(String code, double amount, {String name = 'Utilities'}) => Budget(
        schoolYear: '2026-2027',
        accountCode: code,
        accountName: name,
        amount: amount,
        setByName: 'Grace Mendoza',
        setAt: DateTime(2026, 6, 1),
      );

  /// Books with the given spend posted against each account.
  TrialBalance booksWith(Map<String, double> spendByCode) {
    final entries = <JournalEntry>[];
    var n = 0;
    for (final entry in spendByCode.entries) {
      n++;
      final account = standardChartOfAccounts
          .where((a) => a.code == entry.key)
          .firstOrNull;
      final isRevenue = account?.type == AccountType.revenue;
      entries.add(JournalEntry(
        id: 'je_$n',
        entryNumber: 'JE-2026-000$n',
        date: DateTime(2026, 9, 1),
        memo: 'Spend',
        source: EntrySource.expense,
        postedByName: 'Grace Mendoza',
        postedAt: DateTime(2026, 9, 1),
        lines: isRevenue
            ? [
                JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', entry.value),
                JournalLine.credit(entry.key, account?.name ?? '?', entry.value),
              ]
            : [
                JournalLine.debit(entry.key, account?.name ?? '?', entry.value),
                JournalLine.credit(Accounts.cashInBank, 'Cash in Bank', entry.value),
              ],
      ));
    }
    return TrialBalance.from(chart: standardChartOfAccounts, entries: entries);
  }

  BudgetReport report({
    required List<Budget> budgets,
    required Map<String, double> spend,
  }) =>
      BudgetReport.from(
        schoolYear: '2026-2027',
        budgets: budgets,
        books: booksWith(spend),
      );

  group('a line against its allowance', () {
    test('says what is left', () {
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 120000,
        actual: 45000,
      );
      expect(line.remaining, 75000);
      expect(line.usedFraction, closeTo(0.375, 0.001));
      expect(line.state, BudgetState.within);
    });

    test('an overspend stays negative, so the size of it is visible', () {
      // A report that clamped this at zero would hide how far over.
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 100000,
        actual: 134000,
      );
      expect(line.remaining, -34000);
      expect(line.state, BudgetState.over);
    });

    test('four fifths gone is a warning, not a breach', () {
      // Early enough to do something about it, which is the only point
      // at which a warning is worth anything.
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 100000,
        actual: 80000,
      );
      expect(line.state, BudgetState.near);
      expect(line.remaining, 20000);
    });

    test('spent exactly to the peso is not over', () {
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 100000,
        actual: 100000,
      );
      expect(line.state, BudgetState.near);
      expect(line.remaining, 0);
    });

    test('a centavo over is not over either', () {
      // Floating point leaves residue on anything divided three ways,
      // and a budget flipping to "over" on a billionth of a peso is a
      // warning nobody would believe twice.
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 100000,
        actual: 100000.001,
      );
      expect(line.state, isNot(BudgetState.over));
    });

    test('money on an account nobody budgeted is its own state', () {
      const line = BudgetLine(
        accountCode: '5300',
        accountName: 'Repairs and Maintenance',
        accountType: AccountType.expense,
        budgeted: 0,
        actual: 8000,
      );
      expect(line.state, BudgetState.unbudgeted);
      expect(line.usedFraction, isNull,
          reason: 'a percentage of nothing reads badly on a screen');
    });
  });

  group('asking before spending', () {
    test('says when one more bill would take an account over', () {
      const line = BudgetLine(
        accountCode: '5100',
        accountName: 'Utilities',
        accountType: AccountType.expense,
        budgeted: 100000,
        actual: 92000,
      );
      expect(line.wouldBreachWith(12480), isTrue);
      expect(line.wouldBreachWith(5000), isFalse);
    });

    test('an unbudgeted account can never breach, because there is nothing to breach', () {
      // It is already flagged as unbudgeted; warning twice about the
      // same thing in different words helps nobody.
      const line = BudgetLine(
        accountCode: '5300',
        accountName: 'Repairs',
        accountType: AccountType.expense,
        budgeted: 0,
        actual: 8000,
      );
      expect(line.wouldBreachWith(999999), isFalse);
    });
  });

  group('the report', () {
    test('reads actuals out of the books rather than a running total', () {
      // A stored "spent so far" is a second truth, and it drifts the
      // first time something posts without updating it.
      final r = report(
        budgets: [budget(Accounts.expenseUtilities, 120000)],
        spend: {Accounts.expenseUtilities: 45000},
      );

      final line = r.lineFor(Accounts.expenseUtilities)!;
      expect(line.budgeted, 120000);
      expect(line.actual, 45000);
      expect(line.state, BudgetState.within);
    });

    test('surfaces spending on an account nobody budgeted', () {
      // The thing the report exists to find. One that quietly omitted
      // this would balance and hide it.
      final r = report(
        budgets: [budget(Accounts.expenseUtilities, 120000)],
        spend: {
          Accounts.expenseUtilities: 45000,
          Accounts.expenseRepairs: 8000,
        },
      );

      final line = r.lineFor(Accounts.expenseRepairs)!;
      expect(line.state, BudgetState.unbudgeted);
      expect(line.actual, 8000);
    });

    test('keeps a budgeted account with nothing spent yet', () {
      // Money set aside and untouched is information: it is what is
      // still available.
      final r = report(
        budgets: [budget(Accounts.expenseSupplies, 60000, name: 'Supplies')],
        spend: const {},
      );
      final line = r.lineFor(Accounts.expenseSupplies)!;
      expect(line.budgeted, 60000);
      expect(line.actual, 0);
      expect(line.remaining, 60000);
    });

    test('leaves out accounts with neither a budget nor a spend', () {
      // A school's chart always has a few, and they are noise on a page
      // whose job is to be scanned.
      final r = report(
        budgets: [budget(Accounts.expenseUtilities, 120000)],
        spend: {Accounts.expenseUtilities: 45000},
      );
      expect(r.lineFor(Accounts.expenseRepairs), isNull);
      expect(r.lines, hasLength(1));
    });

    test('never lists a bank balance', () {
      // A school does not budget its cash on hand, and a report that
      // listed it next to Utilities is one nobody reads twice.
      final r = report(
        budgets: [budget(Accounts.expenseUtilities, 120000)],
        spend: {Accounts.expenseUtilities: 45000},
      );
      expect(
        r.lines.any((l) => l.accountType == AccountType.asset),
        isFalse,
      );
      expect(r.lineFor(Accounts.cashInBank), isNull);
    });

    test('budgets income as well as spending', () {
      final r = report(
        budgets: [
          budget(Accounts.revenueTuition, 2000000, name: 'Tuition Revenue'),
          budget(Accounts.expenseSalaries, 1400000, name: 'Salaries and Wages'),
        ],
        spend: {
          Accounts.revenueTuition: 1750000,
          Accounts.expenseSalaries: 1100000,
        },
      );

      expect(r.budgetedFor(AccountType.revenue), 2000000);
      expect(r.actualFor(AccountType.revenue), 1750000);
      expect(r.plannedSurplus, 600000);
      expect(r.actualSurplus, 650000);
    });

    test('puts the lines that need attention first, worst first', () {
      // A report that listed them by account code would make somebody
      // read all of it to find the one that matters.
      final r = report(
        budgets: [
          budget(Accounts.expenseUtilities, 100000),
          budget(Accounts.expenseSupplies, 100000, name: 'Supplies'),
          budget(Accounts.expenseSalaries, 100000, name: 'Salaries'),
        ],
        spend: {
          Accounts.expenseUtilities: 85000, // near
          Accounts.expenseSupplies: 160000, // over by 60k
          Accounts.expenseSalaries: 120000, // over by 20k
          Accounts.expenseRepairs: 5000, // unbudgeted
        },
      );

      final flagged = r.needingAttention.map((l) => l.accountCode).toList();
      expect(flagged.first, Accounts.expenseSupplies, reason: 'worst overspend');
      expect(flagged[1], Accounts.expenseSalaries);
      expect(flagged[2], Accounts.expenseRepairs, reason: 'unbudgeted next');
      expect(flagged.last, Accounts.expenseUtilities, reason: 'merely near');
    });

    test('an empty year says so', () {
      final r = report(budgets: const [], spend: const {});
      expect(r.isEmpty, isTrue);
    });

    test('a budget of zero against real spending reads as unbudgeted', () {
      // Setting a budget to zero is how a line is taken off the plan,
      // and anything spent against it should still be visible.
      final r = report(
        budgets: [budget(Accounts.expenseUtilities, 0)],
        spend: {Accounts.expenseUtilities: 3000},
      );
      expect(r.lineFor(Accounts.expenseUtilities)!.state, BudgetState.unbudgeted);
    });
  });

  group('setting a budget', () {
    const utilities = LedgerAccount(
      code: '5100', name: 'Utilities', type: AccountType.expense);
    const cash = LedgerAccount(
      code: '1000', name: 'Cash on Hand', type: AccountType.asset);

    test('an expense account and a positive amount is fine', () {
      expect(
        reasonBudgetCannotBeSet(
          schoolYear: '2026-2027',
          account: utilities,
          amount: 120000,
        ),
        isNull,
      );
    });

    test('zero is allowed, because that is how a line is removed', () {
      expect(
        reasonBudgetCannotBeSet(
          schoolYear: '2026-2027',
          account: utilities,
          amount: 0,
        ),
        isNull,
      );
    });

    test('a balance sheet account cannot be budgeted', () {
      final reason = reasonBudgetCannotBeSet(
        schoolYear: '2026-2027',
        account: cash,
        amount: 50000,
      );
      expect(reason, contains('Only spending and income'));
      expect(reason, contains('Cash on Hand'));
    });

    test('a negative budget, no account and no year are refused', () {
      expect(
        reasonBudgetCannotBeSet(
          schoolYear: '2026-2027', account: utilities, amount: -1),
        isNotNull,
      );
      expect(
        reasonBudgetCannotBeSet(
          schoolYear: '2026-2027', account: null, amount: 100),
        contains('Choose an account'),
      );
      expect(
        reasonBudgetCannotBeSet(schoolYear: '  ', account: utilities, amount: 100),
        contains('school year'),
      );
    });
  });

  group('the key', () {
    test('is the year and the account, so there cannot be two', () {
      // A school with two budgets for the same account has no way to
      // tell which one anybody meant.
      expect(budget('5100', 1).id, '2026-2027_5100');
      expect(budget('5100', 1).id, budget('5100', 999).id);
    });
  });
}
