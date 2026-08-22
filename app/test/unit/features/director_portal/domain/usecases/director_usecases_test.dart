import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/director_portal/domain/entities/announcement.dart';
import 'package:logicclass/features/director_portal/domain/repositories/director_repository.dart';
import 'package:logicclass/features/director_portal/domain/usecases/announcement_usecases.dart';
import 'package:logicclass/features/director_portal/domain/usecases/approval_usecases.dart';
import 'package:logicclass/features/director_portal/domain/usecases/expense_usecases.dart';
import 'package:logicclass/features/director_portal/domain/usecases/meeting_usecases.dart';

class MockDirectorRepository extends Mock implements DirectorRepository {}

void main() {
  late MockDirectorRepository repository;

  setUp(() {
    repository = MockDirectorRepository();
  });

  group('CreateAnnouncementUseCase', () {
    test('rejects an empty title', () async {
      final useCase = CreateAnnouncementUseCase(repository);
      final result = await useCase(title: '', body: 'Some body', audience: AnnouncementAudience.everyone);
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty body', () async {
      final useCase = CreateAnnouncementUseCase(repository);
      final result = await useCase(title: 'Title', body: '  ', audience: AnnouncementAudience.everyone);
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('CreateMeetingUseCase', () {
    final now = DateTime(2026, 8, 1, 10, 0);

    test('rejects an end time that is not after the start time', () async {
      final useCase = CreateMeetingUseCase(repository);
      final result = await useCase(
        title: 'Faculty Meeting',
        startTime: now,
        endTime: now.subtract(const Duration(minutes: 30)),
        attendeeRoles: ['faculty'],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty attendee list', () async {
      final useCase = CreateMeetingUseCase(repository);
      final result = await useCase(
        title: 'Faculty Meeting',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        attendeeRoles: [],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('DecideApprovalUseCase', () {
    test('requires remarks when rejecting', () async {
      final useCase = DecideApprovalUseCase(repository);
      final result = await useCase(approvalId: 'a1', approve: false);
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.decideApproval(
            approvalId: any(named: 'approvalId'),
            approve: any(named: 'approve'),
            remarks: any(named: 'remarks'),
          ));
    });

    test('does not require remarks when approving', () async {
      when(() => repository.decideApproval(approvalId: 'a1', approve: true, remarks: null))
          .thenAnswer((_) async => const Success(null));

      final useCase = DecideApprovalUseCase(repository);
      final result = await useCase(approvalId: 'a1', approve: true);
      expect(result, isA<Success<void>>());
    });
  });

  group('CreateExpenseUseCase', () {
    test('rejects a non-positive amount', () async {
      final useCase = CreateExpenseUseCase(repository);
      final result = await useCase(
        category: 'Utilities',
        description: 'Electric bill',
        amount: 0,
        date: DateTime.now(),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty category', () async {
      final useCase = CreateExpenseUseCase(repository);
      final result = await useCase(
        category: '',
        description: 'Electric bill',
        amount: 500,
        date: DateTime.now(),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });
}
