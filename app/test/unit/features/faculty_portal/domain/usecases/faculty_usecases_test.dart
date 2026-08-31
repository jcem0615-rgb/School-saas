import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/coursework_item.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/domain/repositories/faculty_repository.dart';
import 'package:logicclass/features/faculty_portal/domain/usecases/coursework_usecases.dart';
import 'package:logicclass/features/faculty_portal/domain/usecases/grade_usecases.dart';

class MockFacultyRepository extends Mock implements FacultyRepository {}

void main() {
  late MockFacultyRepository repository;

  // mocktail needs something concrete to stand in for a GradingScheme
  // before `any()` can match one.
  setUpAll(() => registerFallbackValue(const GradingScheme(weights: [])));

  setUp(() {
    repository = MockFacultyRepository();
  });

  group('CreateCourseworkItemUseCase', () {
    test('requires a due date for gradable types (assignment/project/exam/quiz)', () async {
      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        delivery: CourseworkDelivery.faceToFace,
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
            delivery: CourseworkDelivery.faceToFace,
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
        delivery: CourseworkDelivery.faceToFace,
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
        delivery: CourseworkDelivery.faceToFace,
        type: CourseworkType.lesson,
        title: '',
        description: 'desc',
        subject: 'Math',
        section: '7-A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    // The point of the online mode: the student is not in the room, so
    // the material has to travel with the item. Publishing an online item
    // with nothing attached would leave them with a title and no work.
    test('rejects online coursework with no file attached', () async {
      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        delivery: CourseworkDelivery.online,
        type: CourseworkType.lesson,
        title: 'Module 4',
        description: 'Read the module',
        subject: 'Science',
        section: '7-A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('accepts online coursework once a file is attached', () async {
      when(() => repository.createCourseworkItem(
            delivery: CourseworkDelivery.online,
            type: CourseworkType.lesson,
            title: 'Module 4',
            description: 'Read the module',
            subject: 'Science',
            section: '7-A',
            dueDate: null,
            totalPoints: null,
            published: true,
            attachmentUrl: 'https://example.org/module-4.pdf',
            attachmentName: 'module-4.pdf',
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        delivery: CourseworkDelivery.online,
        type: CourseworkType.lesson,
        title: 'Module 4',
        description: 'Read the module',
        subject: 'Science',
        section: '7-A',
        attachmentUrl: 'https://example.org/module-4.pdf',
        attachmentName: 'module-4.pdf',
      );
      expect(result, isA<Success<void>>());
    });

    test('face-to-face coursework needs no attachment', () async {
      when(() => repository.createCourseworkItem(
            delivery: CourseworkDelivery.faceToFace,
            type: CourseworkType.lesson,
            title: 'Board work',
            description: 'Solve on the board',
            subject: 'Math',
            section: '7-A',
            dueDate: null,
            totalPoints: null,
            published: true,
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateCourseworkItemUseCase(repository);
      final result = await useCase(
        delivery: CourseworkDelivery.faceToFace,
        type: CourseworkType.lesson,
        title: 'Board work',
        description: 'Solve on the board',
        subject: 'Math',
        section: '7-A',
      );
      expect(result, isA<Success<void>>());
    });
  });

  group('UpdateCourseworkItemUseCase', () {
    // An edit that switches an item to online, or strips the file off one
    // that already is, breaks it exactly as badly as creating it that way.
    test('rejects an edit that switches to online without a file', () async {
      final useCase = UpdateCourseworkItemUseCase(repository);
      final result = await useCase(
        itemId: 'cw_1',
        delivery: CourseworkDelivery.online,
        type: CourseworkType.lesson,
        title: 'Module 4',
        description: 'Read the module',
        subject: 'Science',
        section: '7-A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an edit that removes the file from an online item', () async {
      final useCase = UpdateCourseworkItemUseCase(repository);
      final result = await useCase(
        itemId: 'cw_1',
        delivery: CourseworkDelivery.online,
        type: CourseworkType.lesson,
        title: 'Module 4',
        description: 'Read the module',
        subject: 'Science',
        section: '7-A',
        attachmentUrl: '',
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
        component: GradingComponent.writtenWork,
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
        component: GradingComponent.writtenWork,
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
        component: GradingComponent.writtenWork,
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
            component: GradingComponent.writtenWork,
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
        component: GradingComponent.writtenWork,
        score: 100,
        maxScore: 100,
      );
      expect(result, isA<Success<void>>());
    });
  });

  group('SaveGradingSchemeUseCase', () {
    const balanced = SubjectWeights(
      label: 'Everything',
      writtenWork: 30,
      performanceTask: 50,
      quarterlyAssessment: 20,
    );

    test('refuses a group that does not add up to a hundred, and names it', () async {
      // The misconfiguration that does not announce itself. Weights of
      // 30/50/30 produce grades that look entirely plausible and are
      // wrong for every child for a whole year.
      final result = await SaveGradingSchemeUseCase(repository)(
        const GradingScheme(weights: [
          SubjectWeights(
            label: 'Science and Mathematics',
            subjects: ['Science'],
            writtenWork: 40,
            performanceTask: 40,
            quarterlyAssessment: 30,
          ),
          balanced,
        ]),
      );

      final failure = (result as Error).failure;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('Science and Mathematics'));
      verifyNever(() => repository.saveGradingScheme(any()));
    });

    test('refuses a scheme with no groups in it', () async {
      final result = await SaveGradingSchemeUseCase(repository)(
        const GradingScheme(weights: []),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('refuses two catch-all groups', () async {
      // Two groups naming no subjects means the second can never be
      // reached, and a school editing the wrong one would see no change
      // at all.
      final result = await SaveGradingSchemeUseCase(repository)(
        const GradingScheme(weights: [balanced, balanced]),
      );
      final failure = (result as Error).failure;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('catch-all'));
    });

    test('saves a scheme that balances', () async {
      when(() => repository.saveGradingScheme(any()))
          .thenAnswer((_) async => const Success(null));

      final result = await SaveGradingSchemeUseCase(repository)(
        const GradingScheme(weights: [balanced]),
      );

      expect(result, isA<Success<void>>());
      verify(() => repository.saveGradingScheme(any())).called(1);
    });
  });

  group('ConfirmGradingSchemeUseCase', () {
    test('will not confirm weights that do not balance', () async {
      final result = await ConfirmGradingSchemeUseCase(repository)(
        const GradingScheme(weights: [
          SubjectWeights(
            label: 'Broken',
            writtenWork: 10,
            performanceTask: 10,
            quarterlyAssessment: 10,
          ),
        ]),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.confirmGradingScheme());
    });

    test('confirms a scheme that balances', () async {
      when(() => repository.confirmGradingScheme())
          .thenAnswer((_) async => const Success(null));

      final result = await ConfirmGradingSchemeUseCase(repository)(
        const GradingScheme(weights: [
          SubjectWeights(
            label: 'Everything',
            writtenWork: 30,
            performanceTask: 50,
            quarterlyAssessment: 20,
          ),
        ]),
      );

      expect(result, isA<Success<void>>());
      verify(() => repository.confirmGradingScheme()).called(1);
    });
  });
}
