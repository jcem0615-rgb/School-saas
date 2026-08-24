import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/staff_portal/domain/repositories/staff_repository.dart';
import 'package:logicclass/features/staff_portal/domain/usecases/checklist_usecases.dart';
import 'package:logicclass/features/staff_portal/domain/usecases/daily_report_usecases.dart';

class MockStaffRepository extends Mock implements StaffRepository {}

void main() {
  late MockStaffRepository repository;

  setUp(() {
    repository = MockStaffRepository();
  });

  group('AddChecklistItemUseCase', () {
    test('rejects an empty task', () async {
      final useCase = AddChecklistItemUseCase(repository);
      final result = await useCase(task: '  ', date: '2026-07-25');
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('delegates a valid task to the repository', () async {
      when(() => repository.addChecklistItem(task: 'Clean classrooms', date: '2026-07-25'))
          .thenAnswer((_) async => const Success(null));

      final useCase = AddChecklistItemUseCase(repository);
      final result = await useCase(task: 'Clean classrooms', date: '2026-07-25');

      expect(result, isA<Success<void>>());
    });
  });

  group('SubmitDailyReportUseCase', () {
    test('rejects empty content', () async {
      final useCase = SubmitDailyReportUseCase(repository);
      final result = await useCase(date: '2026-07-25', content: '');
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });
}
