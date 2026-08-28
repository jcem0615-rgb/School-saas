import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/data_protection/domain/entities/data_request.dart';
import 'package:logicclass/features/data_protection/domain/entities/privacy_notice.dart';
import 'package:logicclass/features/data_protection/domain/repositories/data_protection_repository.dart';
import 'package:logicclass/features/data_protection/domain/usecases/data_protection_usecases.dart';

class MockRepository extends Mock implements DataProtectionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(DataRequestKind.access);
    registerFallbackValue(DataRequestStatus.open);
  });

  group('DataRequest', () {
    final asOf = DateTime(2026, 8, 1);

    test('an open request past the target is overdue', () {
      expect(
        DataRequest(
          id: 'r',
          requestedByUid: 'u',
          requestedByName: 'A',
          kind: DataRequestKind.access,
          details: 'x',
          requestedAt: asOf.subtract(const Duration(days: DataRequest.targetDays + 1)),
        ).isOverdue(asOf: asOf),
        isTrue,
      );
    });

    test('a request exactly on the target day is not yet overdue', () {
      expect(
        DataRequest(
          id: 'r',
          requestedByUid: 'u',
          requestedByName: 'A',
          kind: DataRequestKind.access,
          details: 'x',
          requestedAt: asOf.subtract(const Duration(days: DataRequest.targetDays)),
        ).isOverdue(asOf: asOf),
        isFalse,
      );
    });

    // An answered request is not a late request, however long it sat.
    test('a closed request is never overdue', () {
      expect(
        DataRequest(
          id: 'r',
          requestedByUid: 'u',
          requestedByName: 'A',
          kind: DataRequestKind.access,
          details: 'x',
          requestedAt: asOf.subtract(const Duration(days: 90)),
          status: DataRequestStatus.actioned,
        ).isOverdue(asOf: asOf),
        isFalse,
      );
    });

    test('names the student when the request is about one', () {
      final about = DataRequest(
        id: 'r',
        requestedByUid: 'u',
        requestedByName: 'Rosalinda Torres',
        kind: DataRequestKind.access,
        details: 'x',
        requestedAt: DateTime(2026, 8, 1),
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
      );
      expect(about.subjectLabel, 'Miguel Torres');
    });
  });

  group('RaiseDataRequestUseCase', () {
    late MockRepository repository;
    setUp(() => repository = MockRepository());

    test('refuses an empty request', () async {
      final result = await RaiseDataRequestUseCase(repository)(
        kind: DataRequestKind.access,
        details: '   ',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.raiseRequest(
            kind: any(named: 'kind'),
            details: any(named: 'details'),
            studentId: any(named: 'studentId'),
            studentName: any(named: 'studentName'),
          ));
    });

    // A person exercising a right should not have to phrase it correctly.
    test('passes anything else through, trimmed', () async {
      when(() => repository.raiseRequest(
            kind: any(named: 'kind'),
            details: any(named: 'details'),
            studentId: any(named: 'studentId'),
            studentName: any(named: 'studentName'),
          )).thenAnswer((_) async => const Success('r1'));

      await RaiseDataRequestUseCase(repository)(
        kind: DataRequestKind.erasure,
        details: '  delete my phone number  ',
      );

      verify(() => repository.raiseRequest(
            kind: DataRequestKind.erasure,
            details: 'delete my phone number',
            studentId: null,
            studentName: null,
          )).called(1);
    });
  });

  group('CloseDataRequestUseCase', () {
    late MockRepository repository;
    setUp(() => repository = MockRepository());

    // A refusal with no reason is the entry a regulator asks about first.
    test('refuses to record a refusal with no reason', () async {
      final result = await CloseDataRequestUseCase(repository)(
        requestId: 'r1',
        status: DataRequestStatus.refused,
        outcome: '  ',
      );
      final failure = (result as Error).failure;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('entitled to be told'));
    });

    test('refuses to mark one done with nothing said about it', () async {
      final result = await CloseDataRequestUseCase(repository)(
        requestId: 'r1',
        status: DataRequestStatus.actioned,
        outcome: '',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('refuses to close a request as still open', () async {
      final result = await CloseDataRequestUseCase(repository)(
        requestId: 'r1',
        status: DataRequestStatus.open,
        outcome: 'done',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('records an outcome, trimmed', () async {
      when(() => repository.closeRequest(
            requestId: any(named: 'requestId'),
            status: any(named: 'status'),
            outcome: any(named: 'outcome'),
          )).thenAnswer((_) async => const Success(null));

      await CloseDataRequestUseCase(repository)(
        requestId: 'r1',
        status: DataRequestStatus.actioned,
        outcome: '  handed over at the registrar  ',
      );

      verify(() => repository.closeRequest(
            requestId: 'r1',
            status: DataRequestStatus.actioned,
            outcome: 'handed over at the registrar',
          )).called(1);
    });
  });

  group('PrivacyNotice', () {
    // The notice is the thing being acknowledged, so an empty section is
    // a promise the school cannot keep.
    test('every category says what, why and who', () {
      expect(PrivacyNotice.categories, isNotEmpty);
      for (final category in PrivacyNotice.categories) {
        expect(category.name.trim(), isNotEmpty);
        expect(category.holds.trim(), isNotEmpty);
        expect(category.why.trim(), isNotEmpty);
        expect(category.seenBy.trim(), isNotEmpty, reason: '${category.name} says who');
      }
    });

    test('covers the collections that actually hold personal data', () {
      final names = PrivacyNotice.categories.map((c) => c.name.toLowerCase()).join(' ');
      for (final expected in [
        'identity',
        'guardian',
        'attendance',
        'academic',
        'fees',
        'emergency',
        'guidance',
        'account',
      ]) {
        expect(names, contains(expected), reason: 'no category covers $expected');
      }
    });

    test('the version is a positive integer that can be compared', () {
      expect(PrivacyNotice.version, greaterThan(0));
    });
  });
}
