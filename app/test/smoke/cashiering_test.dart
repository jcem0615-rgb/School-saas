import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/cashiering/domain/entities/cashier_shift.dart';
import 'package:logicclass/features/cashiering/presentation/controllers/cashiering_controller.dart';
import 'package:logicclass/features/cashiering/presentation/screens/cashier_drawer_screen.dart';
import 'package:logicclass/features/ledger/domain/entities/journal_entry.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';

/// A cashier's drawer, end to end on the demo repositories.
///
/// The control under test is always the same one: the expected figure is
/// worked out from the receipts, not taken from whoever is counting. A
/// count checked against a number the counter supplied is not a control
/// at all.
void main() {
  Future<ProviderContainer> signedInCashier() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );
    // Sign-in has to settle before a controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(cashieringActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  /// Holds the shift list open and waits for it.
  Future<void> settle(ProviderContainer c) async {
    final sub = c.listen(shiftsProvider, (_, __) {});
    addTearDown(sub.close);
    for (var i = 0; i < 60; i++) {
      if (c.read(shiftsProvider).valueOrNull != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('the drawers never arrived');
  }

  /// Takes cash at the window, the way the product does.
  Future<void> takeCash(ProviderContainer c, double amount) async {
    final result = await c.read(paymentRepositoryProvider).recordPayment(
          studentId: 'stu_001',
          amount: amount,
          method: PaymentMethod.cash,
          purpose: PaymentPurpose.tuition,
        );
    expect(result.isSuccess, isTrue, reason: 'the payment should go through');
  }

  double cashVarianceBalance(ProviderContainer c) {
    final store = c.read(demoStoreProvider);
    final trial = TrialBalance.from(
      chart: store.ledgerAccounts.value,
      entries: store.journalEntries.value,
    );
    return trial.rows
            .where((r) => r.account.code == Accounts.expenseCashVariance)
            .firstOrNull
            ?.balance ??
        0;
  }

  group('opening a drawer', () {
    test('starts one, with the float on it', () async {
      final c = await signedInCashier();
      await settle(c);

      final ok = await c.read(cashieringActionControllerProvider.notifier).openShift(
            openShift: c.read(myOpenShiftProvider),
            openingFloat: 2000,
          );

      expect(ok, isTrue);
      final open = c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.isOpen);
      expect(open.openingFloat, 2000);
      expect(open.cashierUid, 'u_registrar');
      expect(open.variance, isNull, reason: 'nobody has counted it');
    });

    test('a second drawer for the same person is refused, naming the first',
        () async {
      // Two open at once means every receipt belongs to both and the
      // reckoning is meaningless.
      final c = await signedInCashier();
      await settle(c);
      final controller = c.read(cashieringActionControllerProvider.notifier);

      await controller.openShift(
          openShift: c.read(myOpenShiftProvider), openingFloat: 2000);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final again = await c.read(cashieringRepositoryProvider).openShift(
            openingFloat: 500,
          );
      expect(again.isError, isTrue);
      expect(again.failureOrNull!.message, contains('already a drawer open'));
    });

    test('a negative float is refused', () async {
      final c = await signedInCashier();
      await settle(c);
      expect(
        await c.read(cashieringActionControllerProvider.notifier).openShift(
              openShift: null,
              openingFloat: -1,
            ),
        isFalse,
      );
    });

    test('the demo opens with no drawer running', () async {
      // Opening one is the first thing a cashier does, and a demo that
      // opens on a drawer already running takes that away from whoever
      // is being shown it.
      final c = await signedInCashier();
      await settle(c);
      expect(c.read(myOpenShiftProvider), isNull);
    });
  });

  group('what the drawer should hold', () {
    test('is the float plus what was taken since it opened', () async {
      final c = await signedInCashier();
      await settle(c);
      await c.read(cashieringActionControllerProvider.notifier).openShift(
            openShift: null,
            openingFloat: 2000,
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final shift = c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.isOpen);

      await takeCash(c, 1500);
      await takeCash(c, 2500);

      final sub = c.listen(reckoningProvider(shift), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final reckoning = c.read(reckoningProvider(shift)).valueOrNull!;
      expect(reckoning.cashCollected, 4000);
      expect(reckoning.expected, 6000);
      expect(reckoning.toDeposit, 4000, reason: 'the float stays');
      expect(reckoning.receiptCount, 2);
    });

    test('leaves out cash somebody else took', () async {
      // A drawer is one person's. Another cashier's receipts belong to
      // their drawer, not this one.
      final c = await signedInCashier();
      await settle(c);
      await c.read(cashieringActionControllerProvider.notifier).openShift(
            openShift: null,
            openingFloat: 2000,
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final shift = c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.isOpen);

      // Seeded payments are all before this drawer opened, and some
      // belong to the admin. Neither should be in the reckoning.
      final sub = c.listen(reckoningProvider(shift), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(c.read(reckoningProvider(shift)).valueOrNull!.cashCollected, 0);
    });
  });

  group('closing it', () {
    Future<CashierShift> openWith(ProviderContainer c, double float) async {
      await c.read(cashieringActionControllerProvider.notifier).openShift(
            openShift: null,
            openingFloat: float,
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.isOpen);
    }

    test('a drawer that balances posts nothing to the books', () async {
      // A pair of zero lines is a journal entry that says nothing.
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);
      await takeCash(c, 1500);

      final entriesBefore = c.read(demoStoreProvider).journalEntries.value.length;
      final closing =
          await c.read(cashieringActionControllerProvider.notifier).closeShift(
                shift: shift,
                countedAmount: 3500,
                expectedAmount: 3500,
              );

      expect(closing, isNotNull);
      expect(closing!.variance, 0);
      expect(
        c.read(demoStoreProvider).journalEntries.value,
        hasLength(entriesBefore),
        reason: 'a balanced drawer has nothing to post',
      );
      final closed = c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.id == shift.id);
      expect(closed.isBalanced, isTrue);
      expect(closed.isOpen, isFalse);
    });

    test('a short drawer charges the difference and keeps the books square',
        () async {
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);
      await takeCash(c, 1500);

      final varianceBefore = cashVarianceBalance(c);
      final closing =
          await c.read(cashieringActionControllerProvider.notifier).closeShift(
                shift: shift,
                countedAmount: 3380,
                expectedAmount: 3500,
                varianceNote: 'Gave the wrong change this morning',
              );

      expect(closing!.variance, -120);
      expect(cashVarianceBalance(c), varianceBefore + 120);

      final store = c.read(demoStoreProvider);
      final trial = TrialBalance.from(
        chart: store.ledgerAccounts.value,
        entries: store.journalEntries.value,
      );
      expect(trial.balances, isTrue);

      final closed = store.cashierShifts.value.firstWhere((s) => s.id == shift.id);
      expect(closed.isShort, isTrue);
      expect(closed.varianceLabel(), 'Short 120.00');
      expect(closed.varianceNote, 'Gave the wrong change this morning');
    });

    test('an overage goes the other way, into the same account', () async {
      // Over is not good news. It is the same control failing in the
      // other direction.
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);
      await takeCash(c, 1500);

      final varianceBefore = cashVarianceBalance(c);
      final closing =
          await c.read(cashieringActionControllerProvider.notifier).closeShift(
                shift: shift,
                countedAmount: 3550,
                expectedAmount: 3500,
                varianceNote: 'Found a fifty under the tray',
              );

      expect(closing!.variance, 50);
      expect(cashVarianceBalance(c), varianceBefore - 50);
    });

    test('a difference with no explanation is refused', () async {
      // The one thing an auditor will ask about and the one thing
      // nobody will remember.
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);

      final closing =
          await c.read(cashieringActionControllerProvider.notifier).closeShift(
                shift: shift,
                countedAmount: 1800,
                expectedAmount: 2000,
              );

      expect(closing, isNull);
      expect(
        c.read(demoStoreProvider).cashierShifts.value
            .firstWhere((s) => s.id == shift.id)
            .isOpen,
        isTrue,
      );
    });

    test('the expected figure is worked out, never taken from the caller',
        () async {
      // The whole control. A caller that claims the drawer should hold
      // what it counted must not thereby make it balance.
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);
      await takeCash(c, 1500);

      final result = await c.read(cashieringRepositoryProvider).closeShift(
            shiftId: shift.id,
            countedAmount: 999,
            varianceNote: 'Trying it on',
          );

      expect(result.isSuccess, isTrue);
      final closed = c.read(demoStoreProvider).cashierShifts.value
          .firstWhere((s) => s.id == shift.id);
      expect(closed.expectedAmount, 3500,
          reason: 'reckoned from the receipts, not from the caller');
      expect(closed.variance, 999 - 3500);
    });

    test('a drawer already closed takes no second count', () async {
      final c = await signedInCashier();
      await settle(c);
      final shift = await openWith(c, 2000);
      await c.read(cashieringActionControllerProvider.notifier).closeShift(
            shift: shift,
            countedAmount: 2000,
            expectedAmount: 2000,
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final again = await c.read(cashieringRepositoryProvider).closeShift(
            shiftId: shift.id,
            countedAmount: 2000,
          );
      expect(again.isError, isTrue);
      expect(again.failureOrNull!.message, contains('already closed'));
    });
  });

  group('the screen', () {
    testWidgets('offers to open one, and lists what has been counted',
        (tester) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await signedInCashier();
        await settle(c);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: CashierDrawerScreen()),
        ),
      );
      // Pumped rather than settled: the loading state is a spinner,
      // which animates for ever.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No drawer open'), findsOneWidget);
      expect(find.text('Open a drawer'), findsOneWidget);
      expect(find.text('Closed drawers'), findsOneWidget);
      // The seeded short drawer is the row somebody has to explain.
      expect(find.textContaining('Short'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
