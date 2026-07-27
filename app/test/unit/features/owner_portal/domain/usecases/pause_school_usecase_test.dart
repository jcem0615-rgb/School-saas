import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/owner_portal/domain/entities/invoice.dart';
import 'package:school_saas/features/owner_portal/domain/repositories/owner_repository.dart';
import 'package:school_saas/features/owner_portal/domain/usecases/pause_school_usecase.dart';
import 'package:school_saas/features/owner_portal/domain/usecases/record_manual_payment_usecase.dart';

class MockOwnerRepository extends Mock implements OwnerRepository {}

void main() {
  late MockOwnerRepository repository;

  setUp(() {
    repository = MockOwnerRepository();
  });

  group('PauseSchoolUseCase', () {
    test('rejects an empty reason without calling the repository', () async {
      final useCase = PauseSchoolUseCase(repository);
      final result = await useCase(schoolId: 'school_1', reason: '   ');

      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.pauseSchool(
          schoolId: any(named: 'schoolId'), reason: any(named: 'reason')));
    });

    test('delegates to the repository with a trimmed reason', () async {
      when(() => repository.pauseSchool(schoolId: 'school_1', reason: 'Non-payment'))
          .thenAnswer((_) async => const Success(null));

      final useCase = PauseSchoolUseCase(repository);
      final result = await useCase(schoolId: 'school_1', reason: '  Non-payment  ');

      expect(result, isA<Success<void>>());
      verify(() => repository.pauseSchool(schoolId: 'school_1', reason: 'Non-payment')).called(1);
    });
  });

  group('RecordManualPaymentUseCase', () {
    test('rejects a non-positive amount', () async {
      final useCase = RecordManualPaymentUseCase(repository);
      final result = await useCase(
        schoolId: 'school_1',
        invoiceId: 'inv_1',
        amount: 0,
        method: PaymentMethod.cash,
      );

      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('requires a reference number for GCash payments', () async {
      final useCase = RecordManualPaymentUseCase(repository);
      final result = await useCase(
        schoolId: 'school_1',
        invoiceId: 'inv_1',
        amount: 1500,
        method: PaymentMethod.gcash,
      );

      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.recordManualPayment(
            schoolId: any(named: 'schoolId'),
            invoiceId: any(named: 'invoiceId'),
            amount: any(named: 'amount'),
            method: any(named: 'method'),
            referenceNumber: any(named: 'referenceNumber'),
          ));
    });

    test('does not require a reference number for cash payments', () async {
      when(() => repository.recordManualPayment(
            schoolId: 'school_1',
            invoiceId: 'inv_1',
            amount: 1500,
            method: PaymentMethod.cash,
            referenceNumber: null,
          )).thenAnswer((_) async => const Success(null));

      final useCase = RecordManualPaymentUseCase(repository);
      final result = await useCase(
        schoolId: 'school_1',
        invoiceId: 'inv_1',
        amount: 1500,
        method: PaymentMethod.cash,
      );

      expect(result, isA<Success<void>>());
    });
  });
}
