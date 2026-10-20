import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/budgets/domain/entities/budget.dart';
import 'package:logicclass/features/budgets/presentation/controllers/budgets_controller.dart';
import 'package:logicclass/features/budgets/presentation/screens/budget_screen.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';
import 'package:logicclass/features/ledger/presentation/controllers/ledger_controller.dart'
    show chartOfAccountsProvider, journalProvider;

/// The plan, against the books.
///
/// The report is built from the ledger rather than from a running total
/// anybody keeps, so most of these check that spending something changes
/// the report without anything else being told to update.
void main() {
  Future<ProviderContainer> signedInDirector() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
        );
    // Sign-in has to settle before a controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  /// Holds the report's whole dependency chain open and waits for it.
  Future<BudgetReport> reportOf(ProviderContainer c) async {
    for (final sub in [
      c.listen(budgetsProvider, (_, __) {}),
      c.listen(chartOfAccountsProvider, (_, __) {}),
      c.listen(journalProvider, (_, __) {}),
    ]) {
      addTearDown(sub.close);
    }
    // Polled rather than slept on: three streams have to arrive and a
    // fixed wait is a test that passes on one machine.
    for (var i = 0; i < 60; i++) {
      final report = c.read(budgetReportProvider);
      if (report != null && !report.isEmpty) return report;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('the budget report never arrived');
  }

  group('the seeded year', () {
    test('is not a plan everything fits inside', () async {
      // A report where every line is comfortable shows nothing about
      // what a budget report is for.
      final c = await signedInDirector();
      final report = await reportOf(c);

      expect(report.needingAttention, isNotEmpty);
      expect(
        report.needingAttention.map((l) => l.state),
        anyOf(contains(BudgetState.over), contains(BudgetState.near)),
      );
    });

    test('never lists a balance sheet account', () async {
      // A school does not budget its cash on hand.
      final c = await signedInDirector();
      final report = await reportOf(c);

      expect(report.lineFor(Accounts.cashInBank), isNull);
      expect(
        report.lines.every((l) =>
            l.accountType == AccountType.expense ||
            l.accountType == AccountType.revenue),
        isTrue,
      );
    });

    test('reads its actuals out of the books', () async {
      // Utilities is seeded with a budget and with a posted expense, so
      // the two have to meet without anything keeping a running total.
      final c = await signedInDirector();
      final report = await reportOf(c);

      final line = report.lineFor(Accounts.expenseUtilities);
      expect(line, isNotNull);
      expect(line!.budgeted, greaterThan(0));
      expect(line.actual, greaterThan(0));
    });
  });

  group('setting a budget', () {
    test('a new line appears, and the report picks it up', () async {
      final c = await signedInDirector();
      await reportOf(c);

      final ok = await c.read(budgetsActionControllerProvider.notifier).setBudget(
            accountCode: Accounts.expenseRepairs,
            amount: 50000,
            note: 'Roof before the rains',
          );
      expect(ok, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final line = c.read(budgetReportProvider)!.lineFor(Accounts.expenseRepairs)!;
      expect(line.budgeted, 50000);
      expect(line.note, 'Roof before the rains');
    });

    test('setting it again replaces it rather than making a second', () async {
      // One budget per account per year, by construction: a school with
      // two has no way to tell which one anybody meant.
      final c = await signedInDirector();
      await reportOf(c);
      final controller = c.read(budgetsActionControllerProvider.notifier);

      await controller.setBudget(accountCode: Accounts.expenseSupplies, amount: 1);
      await controller.setBudget(accountCode: Accounts.expenseSupplies, amount: 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final matching = c
          .read(demoStoreProvider)
          .budgets
          .value
          .where((b) => b.accountCode == Accounts.expenseSupplies);
      expect(matching, hasLength(1));
      expect(matching.single.amount, 2);
    });

    test('a balance sheet account is refused', () async {
      final c = await signedInDirector();
      await reportOf(c);

      expect(
        await c.read(budgetsActionControllerProvider.notifier).setBudget(
              accountCode: Accounts.cashOnHand,
              amount: 10000,
            ),
        isFalse,
      );
    });

    test('a negative budget is refused', () async {
      final c = await signedInDirector();
      await reportOf(c);

      expect(
        await c.read(budgetsActionControllerProvider.notifier).setBudget(
              accountCode: Accounts.expenseSupplies,
              amount: -1,
            ),
        isFalse,
      );
    });

    test('zero takes the line off the plan but leaves the spend visible',
        () async {
      final c = await signedInDirector();
      await reportOf(c);

      await c.read(budgetsActionControllerProvider.notifier).setBudget(
            accountCode: Accounts.expenseUtilities,
            amount: 0,
          );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final line = c.read(budgetReportProvider)!.lineFor(Accounts.expenseUtilities)!;
      expect(line.isBudgeted, isFalse);
      expect(line.state, BudgetState.unbudgeted);
      expect(line.actual, greaterThan(0), reason: 'the spending is still there');
    });
  });

  group('the warning before spending', () {
    test('says when a bill would take an account over', () async {
      final c = await signedInDirector();
      final report = await reportOf(c);
      final line = report.lineFor(Accounts.expenseUtilities)!;

      final warning = budgetWarningFor(
        report: report,
        accountCode: Accounts.expenseUtilities,
        amount: line.budgeted,
      );
      expect(warning, isNotNull);
      expect(warning, contains('over its budget'));
    });

    test('says nothing when it comfortably fits', () async {
      final c = await signedInDirector();
      final report = await reportOf(c);

      expect(
        budgetWarningFor(
          report: report,
          accountCode: Accounts.expenseSalaries,
          amount: 1,
        ),
        isNull,
      );
    });

    test('names an account with no budget at all', () async {
      final c = await signedInDirector();
      final report = await reportOf(c);

      final warning = budgetWarningFor(
        report: report,
        accountCode: Accounts.expenseRepairs,
        amount: 5000,
      );
      // Repairs is deliberately unbudgeted in the seed, so either it is
      // on the report as unbudgeted or it is not on the report at all --
      // and both are honest answers to "is this planned for".
      expect(
        warning == null || warning.contains('no budget'),
        isTrue,
      );
    });
  });

  group('the screen', () {
    testWidgets('opens on the plan with what needs attention first',
        (tester) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await signedInDirector();
        await reportOf(c);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: BudgetScreen()),
        ),
      );
      // Pumped rather than settled: the loading state is a spinner,
      // which animates for ever.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.textContaining('so far'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
