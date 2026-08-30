import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/domain/entities/bank_account.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/domain/entities/payment_settings.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';

/// Paying the school by bank transfer.
///
/// The e-wallet path already existed. What this adds is the school's
/// bank accounts and, more to the point, a record of *which* one the
/// family says they used -- because a cashier holding a reference number
/// and three bank statements has to know where to look.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  PaymentActionController actions(ProviderContainer container) {
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(paymentActionControllerProvider.notifier);
  }

  group('what the school offers', () {
    test('the seeded school takes both e-wallet and transfer', () async {
      final container = await signedInAs(UserRole.parent);
      final settings = container.read(demoStoreProvider).paymentSettings.value;

      expect(settings.payableMethods, contains(PaymentMethod.gcash));
      expect(settings.payableMethods, contains(PaymentMethod.bankTransfer));
      // Cash is over the counter, never a way to pay online.
      expect(settings.payableMethods, isNot(contains(PaymentMethod.cash)));
    });

    test('a closed account is kept on file but not offered', () async {
      final container = await signedInAs(UserRole.parent);
      final settings = container.read(demoStoreProvider).paymentSettings.value;

      expect(settings.bankAccounts.any((a) => !a.isActive), isTrue);
      expect(settings.activeBankAccounts.any((a) => !a.isActive), isFalse);
    });

    test('a school with no bank account does not offer bank transfer', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);

      await actions(container).updatePaymentSettings(bankAccounts: const []);

      final settings = store.paymentSettings.value;
      expect(settings.payableMethods, isNot(contains(PaymentMethod.bankTransfer)));
      // Still payable by e-wallet, which is the point of asking per
      // method rather than once.
      expect(settings.payableMethods, contains(PaymentMethod.gcash));
    });
  });

  group('the registrar editing accounts', () {
    test('adds one without disturbing the QR', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.paymentSettings.value;

      await actions(container).updatePaymentSettings(
        bankAccounts: [
          ...before.bankAccounts,
          const BankAccount(
            id: 'ba_new',
            bankName: 'Metrobank',
            accountName: 'St. Nicholas Academy Inc.',
            accountNumber: '5555 6666 7777',
          ),
        ],
      );

      final after = store.paymentSettings.value;
      expect(after.bankAccounts.length, before.bankAccounts.length + 1);
      // Saving one part of the settings must not wipe another.
      expect(after.accountNumber, before.accountNumber);
      expect(after.instructions, before.instructions);
    });

    test('closes one rather than losing it', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.paymentSettings.value;

      await actions(container).updatePaymentSettings(
        bankAccounts: [
          for (final account in before.bankAccounts)
            if (account.id == 'ba_bpi') account.copyWith(isActive: false) else account,
        ],
      );

      final after = store.paymentSettings.value;
      // Still there -- submissions point at it, and a row that vanishes
      // takes their meaning with it.
      expect(after.bankAccounts.length, before.bankAccounts.length);
      expect(after.bankAccounts.firstWhere((a) => a.id == 'ba_bpi').isActive, isFalse);
      expect(after.activeBankAccounts.any((a) => a.id == 'ba_bpi'), isFalse);
    });
  });

  group('a family paying by transfer', () {
    test('records which account they say they used', () async {
      final container = await signedInAs(UserRole.parent);
      final store = container.read(demoStoreProvider);
      final account = store.paymentSettings.value.activeBankAccounts.first;
      final before = store.paymentSubmissions.value.length;

      final ok = await actions(container).submitOnlinePayment(
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        amount: 5000,
        method: PaymentMethod.bankTransfer,
        purpose: PaymentPurpose.tuition,
        referenceNumber: 'TRF-99887766',
        destinationLabel: account.reconciliationLabel,
      );

      expect(ok, isTrue);
      expect(store.paymentSubmissions.value.length, before + 1);
      final filed = store.paymentSubmissions.value.first;
      expect(filed.method, PaymentMethod.bankTransfer);
      expect(filed.destinationLabel, account.reconciliationLabel);
      expect(filed.destinationLabel, contains(account.accountNumber));
    });

    test('and credits nothing until the cashier approves it', () async {
      final parent = await signedInAs(UserRole.parent);
      final store = parent.read(demoStoreProvider);
      final balanceBefore =
          store.students.value.firstWhere((s) => s.id == 'stu_001').balance;

      await actions(parent).submitOnlinePayment(
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        amount: 5000,
        method: PaymentMethod.bankTransfer,
        purpose: PaymentPurpose.tuition,
        referenceNumber: 'TRF-11223344',
        destinationLabel: store.paymentSettings.value.activeBankAccounts.first
            .reconciliationLabel,
      );

      // Anything that credited an account on the payer's say-so would
      // let anyone clear their own fees by typing a plausible reference.
      expect(
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance,
        balanceBefore,
      );
    });
  });
}
