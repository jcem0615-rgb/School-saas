import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/domain/repositories/payment_repository.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';

/// "The student paid but the balance is not deducting."
///
/// The reported symptom had a cause worth pinning down: a payment
/// recorded against an id that matches no student was accepted. A receipt
/// came back, the payment appeared in the list, and the balance of nobody
/// moved -- which from the counter is indistinguishable from a deduction
/// that failed.
Future<ProviderContainer> _signedInAs(UserRole role) async {
  final container = ProviderContainer(overrides: demoOverrides());
  container.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
  // The demo repositories watch authStateProvider, so a role switch
  // re-subscribes every stream; reading a controller before that lands
  // hands back one that is disposed mid-write.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('a payment deducts the amount from that student', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);
    final before =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;

    final result = await container.read(paymentRepositoryProvider).recordPayment(
          studentId: 'stu_001',
          amount: 1500,
          method: PaymentMethod.cash,
          purpose: PaymentPurpose.tuition,
        );

    expect(result, isA<Success<RecordPaymentOutcome>>());
    final after =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;
    expect(after, before - 1500);
    // The outcome and the record have to agree: the receipt says one
    // figure and the student's record says another otherwise.
    expect((result as Success<RecordPaymentOutcome>).value.newBalance, after);
  });

  test('a payment against an id that matches nobody is refused', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);
    final paymentsBefore = store.payments.value.length;
    final balancesBefore = {
      for (final s in store.students.value) s.id: s.balance,
    };

    // A student number rather than a record id -- the exact mistake a
    // cashier makes, since the number is what is printed on the card.
    final result = await container.read(paymentRepositoryProvider).recordPayment(
          studentId: 'S-2026-000001',
          amount: 1500,
          method: PaymentMethod.cash,
          purpose: PaymentPurpose.tuition,
        );

    expect(result, isA<Error<RecordPaymentOutcome>>());
    // Nothing recorded, and nobody's balance touched. A receipt for a
    // payment that deducted from no student is worse than a refusal.
    expect(store.payments.value.length, paymentsBefore);
    for (final s in store.students.value) {
      expect(s.balance, balancesBefore[s.id]);
    }
  });

  test('centavo amounts do not leave a fraction behind', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);
    final before =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;

    // None of these is exactly representable in binary floating point, so
    // subtracting them one after another accumulates an error. Without
    // rounding on the payment path the balance lands a few
    // ten-thousandths of a centavo off -- it prints as the right figure
    // and fails every equality check made against it, which is the worst
    // combination for a number a school reconciles against.
    const amounts = [1234.56, 2345.67, 3456.78];
    for (final amount in amounts) {
      final result = await container.read(paymentRepositoryProvider).recordPayment(
            studentId: 'stu_001',
            amount: amount,
            method: PaymentMethod.cash,
            purpose: PaymentPurpose.tuition,
          );
      expect(result, isA<Success<RecordPaymentOutcome>>());
    }

    final after =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;
    final expected = ((before - 1234.56 - 2345.67 - 3456.78) * 100).round() / 100;
    expect(after, expected);
  });

  test('a refund puts back exactly what was paid', () async {
    final container = await _signedInAs(UserRole.director);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);
    final repo = container.read(paymentRepositoryProvider);
    final before =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;

    final paid = await repo.recordPayment(
      studentId: 'stu_001',
      amount: 1234.56,
      method: PaymentMethod.cash,
      purpose: PaymentPurpose.tuition,
    );
    final paymentId = (paid as Success<RecordPaymentOutcome>).value.paymentId;

    await repo.recordRefund(paymentId: paymentId, reason: 'Charged twice.');

    final after =
        store.students.value.firstWhere((s) => s.id == 'stu_001').balance;
    expect(after, before);
  });
}
