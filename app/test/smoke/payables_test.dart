import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/ledger/domain/entities/journal_entry.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';
import 'package:logicclass/features/payables/domain/entities/bill.dart';
import 'package:logicclass/features/payables/domain/entities/vendor.dart';
import 'package:logicclass/features/payables/presentation/controllers/payables_controller.dart';
import 'package:logicclass/features/payables/presentation/screens/payables_screen.dart';

/// What the school owes, end to end on the demo repositories.
///
/// The property everything here protects is that the payables ledger and
/// the books agree. Every bill, payment and void posts its own entry, so
/// the trial balance is checked after each one -- a payables list that
/// disagrees with the ledger is the gap this module exists to close.
void main() {
  Future<ProviderContainer> signedInDirector() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
        );
    // Sign-in has to settle before the controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(payablesActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  /// The sentence a refusal is made of.
  ///
  /// Read off the result rather than the action controller's error
  /// state: the controller is autoDispose and the demo repositories
  /// watch authStateProvider, so an emission mid-call can rebuild it and
  /// take the error with it. The returned Result cannot be lost that
  /// way, and it is the same message the screen shows.
  String refusalFrom(Result<Object?> result) =>
      result.failureOrNull?.message ?? '';

  /// The books, over every entry rather than the current period.
  TrialBalance trialOf(ProviderContainer c) {
    final store = c.read(demoStoreProvider);
    return TrialBalance.from(
      chart: store.ledgerAccounts.value,
      entries: store.journalEntries.value,
    );
  }

  double payableBalance(ProviderContainer c) {
    final row = trialOf(c)
        .rows
        .where((r) => r.account.code == Accounts.payableTrade)
        .firstOrNull;
    return row?.balance ?? 0;
  }

  Bill billNamed(ProviderContainer c, String id) =>
      c.read(demoStoreProvider).bills.value.firstWhere((b) => b.id == id);

  List<BillLine> someLines() => const [
        BillLine(
          accountCode: Accounts.expenseSupplies,
          accountName: 'Supplies',
          description: 'Bond paper',
          amount: 3000,
        ),
      ];

  group('the seeded payables', () {
    test('show a spread of ages, not one column', () async {
      // A demo where everything is current shows a report with one
      // column filled in, which teaches nothing about what it is for.
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final ageing = c.read(payablesAgeingProvider);
      expect(ageing.isEmpty, isFalse);
      expect(ageing.overdue, greaterThan(0));
      final used = AgeingBucket.values
          .where((b) => (ageing.totals[b] ?? 0) > 0)
          .length;
      expect(used, greaterThan(1), reason: 'the report should span buckets');
    });

    test('leave the settled bill off the ageing report', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final paid = billNamed(c, 'bill_004');
      expect(paid.isPaid, isTrue);
      expect(
        c.read(payablesAgeingProvider).byVendor.keys,
        isNot(contains(paid.vendorName)),
      );
    });
  });

  group('recording a bill', () {
    test('raises the liability in the books at the same moment', () async {
      // What was bought is an expense the moment it is delivered, not
      // the day it is paid for. That is the whole of why AP exists as
      // something separate from a cash book.
      final c = await signedInDirector();
      final owedBefore = payableBalance(c);

      final ok = await c.read(payablesActionControllerProvider.notifier).recordBill(
            vendorId: 'ven_002',
            billNumber: 'SI-NEW-1',
            billDate: DateTime.now(),
            dueDate: DateTime.now().add(const Duration(days: 30)),
            lines: someLines(),
          );

      expect(ok, isTrue);
      expect(payableBalance(c), owedBefore + 3000);
      expect(trialOf(c).balances, isTrue);

      final entry = c
          .read(demoStoreProvider)
          .journalEntries
          .value
          .firstWhere((e) => e.source == EntrySource.bill);
      expect(entry.memo, contains('SI-NEW-1'));
    });

    test('the same invoice twice is refused', () async {
      // The most common mistake in a payables ledger, and it pays a
      // supplier twice.
      final c = await signedInDirector();
      final controller = c.read(payablesActionControllerProvider.notifier);
      final before = c.read(demoStoreProvider).bills.value.length;

      final ok = await controller.recordBill(
        vendorId: 'ven_002',
        billNumber: 'SI-99321', // already seeded against this vendor
        billDate: DateTime.now(),
        dueDate: DateTime.now(),
        lines: someLines(),
      );

      expect(ok, isFalse);
      expect(c.read(demoStoreProvider).bills.value, hasLength(before));

      // And the refusal says which invoice, so somebody can go and look.
      final again = await c.read(payablesRepositoryProvider).recordBill(
            vendorId: 'ven_002',
            billNumber: 'SI-99321',
            billDate: DateTime.now(),
            dueDate: DateTime.now(),
            lines: someLines(),
          );
      expect(refusalFrom(again), contains('already recorded'));
      expect(refusalFrom(again), contains('SI-99321'));
    });

    test('the same number from a different supplier is fine', () async {
      final c = await signedInDirector();
      expect(
        await c.read(payablesActionControllerProvider.notifier).recordBill(
              vendorId: 'ven_001',
              billNumber: 'SI-99321',
              billDate: DateTime.now(),
              dueDate: DateTime.now(),
              lines: someLines(),
            ),
        isTrue,
      );
    });

    test('a bill with no invoice number is refused', () async {
      final c = await signedInDirector();
      expect(
        await c.read(payablesActionControllerProvider.notifier).recordBill(
              vendorId: 'ven_002',
              billNumber: '   ',
              billDate: DateTime.now(),
              dueDate: DateTime.now(),
              lines: someLines(),
            ),
        isFalse,
      );
    });

    test('a bill due before it was issued is refused', () async {
      final c = await signedInDirector();
      expect(
        await c.read(payablesActionControllerProvider.notifier).recordBill(
              vendorId: 'ven_002',
              billNumber: 'SI-BACKWARDS',
              billDate: DateTime.now(),
              dueDate: DateTime.now().subtract(const Duration(days: 10)),
              lines: someLines(),
            ),
        isFalse,
      );
    });
  });

  group('paying a bill', () {
    test('clears the liability and the cash, and keeps the books square',
        () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final bill = billNamed(c, 'bill_001');
      final owedBefore = payableBalance(c);

      final ok = await c.read(payablesActionControllerProvider.notifier).payBill(
            bill: bill,
            amount: bill.outstanding,
            paidFromAccountCode: Accounts.cashInBank,
            reference: 'Cheque 004500',
          );

      expect(ok, isTrue);
      expect(payableBalance(c), owedBefore - bill.outstanding);
      expect(trialOf(c).balances, isTrue);

      final after = billNamed(c, 'bill_001');
      expect(after.isPaid, isTrue);
      expect(after.effectiveStatus, BillStatus.paid);
      expect(after.payments.last.reference, 'Cheque 004500');
    });

    test('a part payment leaves the rest outstanding', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final bill = billNamed(c, 'bill_003');
      await c.read(payablesActionControllerProvider.notifier).payBill(
            bill: bill,
            amount: 1800,
            paidFromAccountCode: Accounts.cashOnHand,
          );

      final after = billNamed(c, 'bill_003');
      expect(after.outstanding, 6000);
      expect(after.effectiveStatus, BillStatus.partiallyPaid);
      expect(trialOf(c).balances, isTrue);
    });

    test('overpaying is refused, and says what is left', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final bill = billNamed(c, 'bill_002'); // 12000, 5000 paid
      final ok = await c.read(payablesActionControllerProvider.notifier).payBill(
            bill: bill,
            amount: 9000,
            paidFromAccountCode: Accounts.cashInBank,
          );

      expect(ok, isFalse);

      // Said in pesos: "invalid" tells a person nothing about what to
      // type instead.
      final direct = await c.read(payablesRepositoryProvider).payBill(
            billId: bill.id,
            amount: 9000,
            paidFromAccountCode: Accounts.cashInBank,
          );
      expect(refusalFrom(direct), contains('7000.00'));
    });

    test('a settled bill takes no more money', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final ok = await c.read(payablesActionControllerProvider.notifier).payBill(
            bill: billNamed(c, 'bill_004'),
            amount: 100,
            paidFromAccountCode: Accounts.cashOnHand,
          );
      expect(ok, isFalse);
    });
  });

  group('voiding a bill', () {
    test('reverses the liability and leaves the bill on the ledger', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final bill = billNamed(c, 'bill_003');
      final owedBefore = payableBalance(c);
      final countBefore = c.read(demoStoreProvider).bills.value.length;

      final ok = await c.read(payablesActionControllerProvider.notifier).voidBill(
            bill: bill,
            reason: 'Duplicate of SI-98003',
          );

      expect(ok, isTrue);
      // Nothing deleted: the bill stays, marked void.
      expect(c.read(demoStoreProvider).bills.value, hasLength(countBefore));
      final after = billNamed(c, 'bill_003');
      expect(after.isVoid, isTrue);
      expect(after.voidReason, 'Duplicate of SI-98003');
      expect(after.isOutstanding, isFalse);

      expect(payableBalance(c), owedBefore - bill.total);
      expect(trialOf(c).balances, isTrue);
    });

    test('a bill with money against it cannot be voided', () async {
      // The cash really did leave. Pretending the bill never existed
      // would leave a payment pointing at nothing.
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final ok = await c.read(payablesActionControllerProvider.notifier).voidBill(
            bill: billNamed(c, 'bill_002'),
            reason: 'Changed my mind',
          );

      expect(ok, isFalse);

      final direct = await c.read(payablesRepositoryProvider).voidBill(
            billId: 'bill_002',
            reason: 'Changed my mind',
          );
      expect(refusalFrom(direct), contains('credit from the supplier'));
    });

    test('a void with no reason is refused', () async {
      final c = await signedInDirector();
      final sub = c.listen(billsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        await c.read(payablesActionControllerProvider.notifier).voidBill(
              bill: billNamed(c, 'bill_003'),
              reason: ' ',
            ),
        isFalse,
      );
    });
  });

  group('the supplier list', () {
    test('a new supplier is given an id', () async {
      final c = await signedInDirector();
      final before = c.read(demoStoreProvider).vendors.value.length;

      final ok = await c.read(payablesActionControllerProvider.notifier).saveVendor(
            const Vendor(id: '', name: 'Maynilad', paymentTermsDays: 20),
          );

      expect(ok, isTrue);
      final vendors = c.read(demoStoreProvider).vendors.value;
      expect(vendors, hasLength(before + 1));
      expect(vendors.firstWhere((v) => v.name == 'Maynilad').id, isNotEmpty);
    });

    test('a supplier with no name, or silly terms, is refused', () async {
      final c = await signedInDirector();
      final controller = c.read(payablesActionControllerProvider.notifier);

      expect(await controller.saveVendor(const Vendor(id: '', name: '  ')), isFalse);
      expect(
        await controller.saveVendor(
          const Vendor(id: '', name: 'Someone', paymentTermsDays: -5),
        ),
        isFalse,
      );
      expect(
        await controller.saveVendor(
          const Vendor(id: '', name: 'Someone', paymentTermsDays: 900),
        ),
        isFalse,
      );
    });
  });

  group('the screen', () {
    testWidgets('opens on what is owed, past due called out', (tester) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await signedInDirector();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: PayablesScreen()),
        ),
      );
      // Pumped rather than settled: the loading state is a spinner,
      // which animates for ever. The real wait is the demo
      // repositories' latency, on the real clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Owed as at'), findsOneWidget);
      expect(find.textContaining('past due'), findsOneWidget);
      expect(find.text('National Book Store'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
