import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/domain/entities/approval_request.dart';
import 'package:logicclass/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';

/// The demo is a claim about the product, and it is also the fixture that
/// nearly every test in this app runs against. Both of those break the
/// same way: when the demo writes a shape the server never writes, a
/// prospect is shown something that will not happen, and a test that
/// should have caught a bug passes instead.
///
/// The refund pair is where that bites. `recordRefund.ts` flips the
/// original to `refunded` and writes the negative row as `completed`;
/// the demo marked both rows `refunded`. Against demo data, "total the
/// completed ones" looks like a sound way to add up a day. Against real
/// data it drops the payment being reversed and keeps the negative row,
/// which is what the Director's dashboard did until it was fixed.
///
/// So these assert the demo against the server's shape, quoting the
/// callable each one mirrors. They are deliberately about shape rather
/// than arithmetic; the arithmetic has its own tests.
void main() {
  ProviderContainer demo() {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.admin),
        );
    return container;
  }

  group('a refund, as recordRefund.ts writes it', () {
    test('leaves the original marked refunded and the new row completed',
        () async {
      final container = demo();
      final store = container.read(demoStoreProvider);
      final repo = container.read(paymentRepositoryProvider);

      final original = store.payments.value.firstWhere(
        (p) => !p.isRefund && p.status == PaymentStatus.completed,
      );
      final result = await repo.recordRefund(
        paymentId: original.id,
        reason: 'Paid twice at the counter.',
      );
      expect(result.isSuccess, isTrue);

      final after = store.payments.value;
      final reversed = after.firstWhere((p) => p.id == original.id);
      final refundRow = after.firstWhere((p) => p.refundOf == original.id);

      // recordRefund.ts: tx.update(originalRef, {status: "refunded"}) and
      // tx.set(refundRef, {..., status: "completed"}).
      expect(reversed.status, PaymentStatus.refunded,
          reason: 'the payment being reversed is the one that flips');
      expect(refundRow.status, PaymentStatus.completed,
          reason: 'the negative row is a completed transaction, not a '
              'refunded one -- a status filter that gets this wrong is how '
              'the dashboard double-counted refunds');
      expect(refundRow.amount, -original.amount);
    });

    test('numbers the refund off the receipt it reverses', () async {
      final container = demo();
      final store = container.read(demoStoreProvider);
      final repo = container.read(paymentRepositoryProvider);

      final original = store.payments.value.firstWhere(
        (p) => !p.isRefund && p.status == PaymentStatus.completed,
      );
      await repo.recordRefund(paymentId: original.id, reason: 'Overpayment.');

      final refundRow =
          store.payments.value.firstWhere((p) => p.refundOf == original.id);
      // recordRefund.ts: receiptNumber: `${original.receiptNumber}-R`.
      expect(refundRow.receiptNumber, '${original.receiptNumber}-R');
    });
  });

  group('a receipt number, as balanceMath.ts formats it', () {
    test('is an RC- series, not the official-receipt one', () async {
      final container = demo();
      final store = container.read(demoStoreProvider);
      final repo = container.read(paymentRepositoryProvider);

      final result = await repo.recordPayment(
        studentId: store.students.value.first.id,
        amount: 1500,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
      );
      expect(result.isSuccess, isTrue);

      // formatReceiptNumber: `RC-${year}-${6 digits}`. OR- is the BIR
      // serial off a printed booklet, which is `officialReceiptNo` and a
      // different register entirely.
      expect(
        RegExp(r'^RC-\d{4}-\d{6}$').hasMatch(result.valueOrNull!.receiptNumber),
        isTrue,
        reason: 'got ${result.valueOrNull!.receiptNumber}',
      );
    });

    test('and every seeded receipt reads the same way', () {
      final container = demo();
      for (final payment in container.read(demoStoreProvider).payments.value) {
        expect(payment.receiptNumber, startsWith('RC-'),
            reason: 'a demo receipt a prospect can open should look like one '
                'the product prints');
      }
    });
  });

  group('nobody decides their own request', () {
    Future<ApprovalRequest> fileAs(
      ProviderContainer container,
      UserRole role,
      String title,
    ) async {
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == role),
          );
      await container.read(directorRepositoryProvider).createApprovalRequest(
            type: 'material_request',
            title: title,
            details: const {'quantity': 1},
          );
      return container
          .read(demoStoreProvider)
          .approvals
          .value
          .firstWhere((a) => a.title == title);
    }

    test('an admin cannot decide the request they filed', () async {
      final container = demo();
      final mine = await fileAs(container, UserRole.admin, 'Two reams of bond paper');

      final result = await container
          .read(directorRepositoryProvider)
          .decideApproval(approvalId: mine.id, approve: true);

      expect(result.isSuccess, isFalse,
          reason: 'firestore.rules refuses this, and the reason the Director '
              'keeps approvals at all is that somebody else has to decide '
              'what the Admin filed');
      final unchanged = container
          .read(demoStoreProvider)
          .approvals
          .value
          .firstWhere((a) => a.id == mine.id);
      expect(unchanged.status, ApprovalStatus.pending);
    });

    test('but somebody else can', () async {
      final container = demo();
      final theirs = await fileAs(container, UserRole.admin, 'A box of chalk');

      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
          );
      final result = await container
          .read(directorRepositoryProvider)
          .decideApproval(approvalId: theirs.id, approve: true);

      expect(result.isSuccess, isTrue);
      final decided = container
          .read(demoStoreProvider)
          .approvals
          .value
          .firstWhere((a) => a.id == theirs.id);
      expect(decided.status, ApprovalStatus.approved);
      expect(decided.decidedByRole, 'director');
    });

    test('and a request carries the uid that decides the question', () async {
      final container = demo();
      final mine = await fileAs(container, UserRole.director, 'A new stapler');
      expect(mine.requestedByUid, isNotNull,
          reason: 'a name is not an identity; the screen cannot tell whose '
              'request this is without it');
      expect(
        mine.requestedByUid,
        DemoStore.demoAccounts
            .firstWhere((a) => a.role == UserRole.director)
            .uid,
      );
    });
  });
}
