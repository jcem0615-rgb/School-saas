import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/guidance_portal/domain/entities/guidance_record.dart';
import 'package:school_saas/features/guidance_portal/domain/repositories/guidance_repository.dart';
import 'package:school_saas/features/guidance_portal/domain/usecases/guidance_record_usecases.dart';
import 'package:school_saas/features/guidance_portal/domain/usecases/summons_usecases.dart';

class MockGuidanceRepository extends Mock implements GuidanceRepository {}

void main() {
  late MockGuidanceRepository repository;

  setUp(() {
    repository = MockGuidanceRepository();
  });

  group('CreateGuidanceRecordUseCase', () {
    test('rejects empty notes', () async {
      final useCase = CreateGuidanceRecordUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        category: GuidanceCategory.behavioral,
        notes: '   ',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a missing student id', () async {
      final useCase = CreateGuidanceRecordUseCase(repository);
      final result = await useCase(
        studentId: '',
        studentName: 'Juan',
        category: GuidanceCategory.behavioral,
        notes: 'Some notes',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('CreateSummonsUseCase', () {
    test('rejects an empty reason', () async {
      final useCase = CreateSummonsUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        reason: '',
        scheduledDate: DateTime.now(),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });
}
