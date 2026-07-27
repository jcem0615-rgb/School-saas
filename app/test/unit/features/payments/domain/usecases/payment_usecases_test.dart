import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/payments/domain/entities/payment.dart';
import 'package:school_saas/features/payments/domain/repositories/payment_repository.dart';
import 'package:school_saas/features/payments/domain/usecases/record_payment_usecase.dart';
import 'package:school_saas/features/payments/domain/usecases/record_refund_usecase.dart';

class MockPaymentRepository extends Mock implements PaymentRepository {}

void main() {
  late MockPaymentRepository repository;

  setUp(() {
    repository = MockPaymentRepository();
  });

  group('RecordPaymentUseCase', () {
    test('rejects a non-positive amount', () async {
      final useCase = RecordPaymentUseCase(repository);
      final result = await useCase(
        studentId: 'student_1',
        amount: 0,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a missing student id', () async {
      final useCase = RecordPaymentUseCase(repository);
      final result = await useCase(
        studentId: '  ',
        amount: 500,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('requires a reference number for bank transfer', () async {
      final useCase = RecordPaymentUseCase(repository);
      final result = await useCase(
        studentId: 'student_1',
        amount: 500,
        method: PaymentMethod.bankTransfer,
        purpose: PaymentPurpose.tuition,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.recordPayment(
            studentId: any(named: 'studentId'),
            amount: any(named: 'amount'),
            method: any(named: 'method'),
            purpose: any(named: 'purpose'),
            referenceNumber: any(named: 'referenceNumber'),
          ));
    });

    test('delegates to the repository on valid cash payment', () async {
      when(() => repository.recordPayment(
            studentId: 'student_1',
            amount: 500,
            method: PaymentMethod.cash,
            purpose: PaymentPurpose.tuition,
            referenceNumber: null,
          )).thenAnswer((_) async => const Success(
            RecordPaymentOutcome(paymentId: 'p1', receiptNumber: 'RC-2026-000001', newBalance: 2500),
          ));

      final useCase = RecordPaymentUseCase(repository);
      final result = await useCase(
        studentId: 'student_1',
        amount: 500,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
      );

      expect(result, isA<Success<RecordPaymentOutcome>>());
      expect((result as Success).value.receiptNumber, 'RC-2026-000001');
    });
  });

  group('RecordRefundUseCase', () {
    test('rejects an empty reason', () async {
      final useCase = RecordRefundUseCase(repository);
      final result = await useCase(paymentId: 'p1', reason: '   ');
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.recordRefund(
            paymentId: any(named: 'paymentId'),
            reason: any(named: 'reason'),
          ));
    });

    test('delegates to the repository with a valid reason', () async {
      when(() => repository.recordRefund(paymentId: 'p1', reason: 'Overpayment'))
          .thenAnswer((_) async => const Success(null));

      final useCase = RecordRefundUseCase(repository);
      final result = await useCase(paymentId: 'p1', reason: 'Overpayment');

      expect(result, isA<Success<void>>());
    });
  });
}
