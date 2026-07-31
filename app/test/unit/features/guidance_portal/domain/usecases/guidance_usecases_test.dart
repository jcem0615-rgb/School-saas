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

  // mocktail needs a concrete instance before any(named:) can stand in for
  // a non-nullable enum parameter.
  setUpAll(() {
    registerFallbackValue(GuidanceCategory.other);
  });

  setUp(() {
    repository = MockGuidanceRepository();
  });

  group('CreateGuidanceRecordUseCase', () {
    test('rejects empty notes', () async {
      final useCase = CreateGuidanceRecordUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        section: 'Grade 10 - Rizal',
        category: GuidanceCategory.behavioral,
        notes: '   ',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a missing section', () async {
      // Section is what a note is always filed against, so it is the
      // required field -- naming a student within it is optional.
      final useCase = CreateGuidanceRecordUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        section: '  ',
        category: GuidanceCategory.behavioral,
        notes: 'Some notes',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('allows a section-level note with no student, normalising blank to null', () async {
      when(() => repository.createGuidanceRecord(
            studentId: any(named: 'studentId'),
            studentName: any(named: 'studentName'),
            section: any(named: 'section'),
            category: any(named: 'category'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateGuidanceRecordUseCase(repository);
      final result = await useCase(
        studentId: '',
        studentName: '',
        section: 'Grade 10 - Rizal',
        category: GuidanceCategory.behavioral,
        notes: 'Whole class briefed on the tardiness policy',
      );

      expect(result, isA<Success<void>>());
      // Blank must become null, not '': firestore.rules keys its scoping on
      // studentId being absent, and '' would read as a note pointing at a
      // student that does not exist.
      verify(() => repository.createGuidanceRecord(
            studentId: null,
            studentName: null,
            section: 'Grade 10 - Rizal',
            category: GuidanceCategory.behavioral,
            notes: 'Whole class briefed on the tardiness policy',
          )).called(1);
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
