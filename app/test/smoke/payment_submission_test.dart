import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/core/storage/upload_providers.dart';
import 'package:school_saas/core/storage/upload_repository.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/payments/domain/entities/payment.dart';
import 'package:school_saas/features/payments/domain/entities/payment_submission.dart';
import 'package:school_saas/features/payments/presentation/controllers/payment_controller.dart';

/// The property this whole feature exists to establish: a family saying
/// they paid must not move a balance. Only a reviewer approving does.
void main() {
  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    return c;
  }

  Future<void> signIn(ProviderContainer c, UserRole role) async {
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    // The demo repositories watch authStateProvider and rebuild on its
    // first emission, which would dispose anything read before it lands.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  double balanceOf(ProviderContainer c, String studentId) =>
      c.read(demoStoreProvider).students.value.firstWhere((s) => s.id == studentId).balance;

  test('submitting does not credit the account; approving does', () async {
    final c = await container();
    await signIn(c, UserRole.student);
    final sub = c.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final before = balanceOf(c, 'stu_001');

    final receipt = await c.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.paymentReceipts,
          fileName: 'gcash.png',
          bytes: Uint8List.fromList(utf8.encode('screenshot')),
          contentType: 'image/png',
        );
    final uploaded = switch (receipt) {
      Success<UploadedFile>(:final value) => value,
      Error<UploadedFile>(:final failure) => fail(failure.message),
    };

    final filed = await c.read(paymentActionControllerProvider.notifier).submitOnlinePayment(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          amount: 2500,
          method: PaymentMethod.gcash,
          purpose: PaymentPurpose.tuition,
          referenceNumber: 'GC-1234567',
          receiptUrl: uploaded.url,
          receiptFileName: uploaded.fileName,
        );
    expect(filed, isTrue);

    // The claim exists, but the money has not moved.
    expect(balanceOf(c, 'stu_001'), before,
        reason: 'a submission must not credit the account on the payer\'s say-so');

    final pending = await c.read(paymentRepositoryProvider).watchSubmissions().first;
    final mine = pending.firstWhere((s) => s.referenceNumber == 'GC-1234567');
    expect(mine.status, SubmissionStatus.pending);
    expect(mine.receiptUrl, isNotNull);

    // Now the cashier verifies it.
    await signIn(c, UserRole.registrar);
    final sub2 = c.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub2.close);

    final approved = await c
        .read(paymentActionControllerProvider.notifier)
        .decideSubmission(submissionId: mine.id, approve: true);
    expect(approved, isTrue);

    expect(balanceOf(c, 'stu_001'), before - 2500,
        reason: 'approval is what credits the account');

    // And a real Payment now exists, with the family's reference carried
    // through so the trail from claim to record survives.
    final payments =
        await c.read(paymentRepositoryProvider).watchPaymentsForStudent('stu_001').first;
    expect(payments.any((p) => p.referenceNumber == 'GC-1234567'), isTrue);
  });

  test('rejecting leaves the balance untouched and requires a reason', () async {
    final c = await container();
    await signIn(c, UserRole.registrar);
    final sub = c.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    // sub_0001 is the seeded pending submission for stu_003.
    final before = balanceOf(c, 'stu_003');

    final noReason = await c
        .read(paymentActionControllerProvider.notifier)
        .decideSubmission(submissionId: 'sub_0001', approve: false, remarks: '   ');
    expect(noReason, isFalse, reason: 'a rejection with no reason tells the family nothing');

    final rejected = await c.read(paymentActionControllerProvider.notifier).decideSubmission(
          submissionId: 'sub_0001',
          approve: false,
          remarks: 'Reference not found in the school account.',
        );
    expect(rejected, isTrue);
    expect(balanceOf(c, 'stu_003'), before);
  });

  test('a submission cannot be decided twice', () async {
    final c = await container();
    await signIn(c, UserRole.registrar);
    final sub = c.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final first = await c
        .read(paymentActionControllerProvider.notifier)
        .decideSubmission(submissionId: 'sub_0001', approve: true);
    expect(first, isTrue);

    final balanceAfterFirst = balanceOf(c, 'stu_003');
    final second = await c
        .read(paymentActionControllerProvider.notifier)
        .decideSubmission(submissionId: 'sub_0001', approve: true);

    expect(second, isFalse, reason: 'double approval would credit the same money twice');
    expect(balanceOf(c, 'stu_003'), balanceAfterFirst);
  });

  test('a submission without a reference number is refused', () async {
    final c = await container();
    await signIn(c, UserRole.student);
    final sub = c.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final filed = await c.read(paymentActionControllerProvider.notifier).submitOnlinePayment(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          amount: 1000,
          method: PaymentMethod.gcash,
          purpose: PaymentPurpose.tuition,
          referenceNumber: '   ',
        );
    // The reference is the only thing a cashier can check against the
    // school's e-wallet, so a submission without one is unverifiable.
    expect(filed, isFalse);
  });
}
