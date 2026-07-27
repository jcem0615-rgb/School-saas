import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/faculty_portal/domain/entities/coursework_item.dart';
import 'package:school_saas/features/faculty_portal/domain/repositories/faculty_repository.dart';
import 'package:school_saas/features/faculty_portal/domain/usecases/coursework_usecases.dart';
import 'package:school_saas/features/faculty_portal/domain/usecases/grade_usecases.dart';

class MockFacultyRepository extends Mock implements FacultyRepository {}

void main() {
  late MockFacultyRepository repository;

  setUp(() {
    repository = MockFacultyRepository();
  });

  group('CreateCourseworkItemUseCase', () {
    test('requires a due date for gradable types (assignment/project/exam/quiz)', () async {
      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        type: CourseworkType.assignment,
        title: 'Essay',
        description: 'Write an essay',
        subject: 'English',
        section: '7-A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('does NOT require a due date for a Lesson Plan', () async {
      when(() => repository.createCourseworkItem(
            type: CourseworkType.lessonPlan,
            title: 'Photosynthesis',
            description: 'Intro lesson',
            subject: 'Science',
            section: '7-A',
            dueDate: null,
            totalPoints: null,
            published: true,
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        type: CourseworkType.lessonPlan,
        title: 'Photosynthesis',
        description: 'Intro lesson',
        subject: 'Science',
        section: '7-A',
      );
      expect(result, isA<Success<void>>());
    });

    test('rejects an empty title', () async {
      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        type: CourseworkType.lesson,
        title: '',
        description: 'desc',
        subject: 'Math',
        section: '7-A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('SubmitGradeUseCase', () {
    test('rejects a score greater than max score', () async {
      final useCase = SubmitGradeUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        subject: 'Math',
        section: '7-A',
        term: 'Q1',
        score: 110,
        maxScore: 100,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a negative score', () async {
      final useCase = SubmitGradeUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        subject: 'Math',
        section: '7-A',
        term: 'Q1',
        score: -5,
        maxScore: 100,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a zero max score', () async {
      final useCase = SubmitGradeUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        subject: 'Math',
        section: '7-A',
        term: 'Q1',
        score: 0,
        maxScore: 0,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('accepts a valid score at the boundary (score == maxScore)', () async {
      when(() => repository.submitGrade(
            studentId: 's1',
            studentName: 'Juan',
            subject: 'Math',
            section: '7-A',
            term: 'Q1',
            score: 100,
            maxScore: 100,
            courseworkItemId: null,
            remarks: null,
          )).thenAnswer((_) async => const Success(null));

      final useCase = SubmitGradeUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        studentName: 'Juan',
        subject: 'Math',
        section: '7-A',
        term: 'Q1',
        score: 100,
        maxScore: 100,
      );
      expect(result, isA<Success<void>>());
    });
  });
}
