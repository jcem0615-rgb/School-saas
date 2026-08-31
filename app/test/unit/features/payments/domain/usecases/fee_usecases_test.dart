import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/repositories/payment_repository.dart';
import 'package:logicclass/features/payments/domain/usecases/fee_usecases.dart';

class MockPaymentRepository extends Mock implements PaymentRepository {}

const _tuition = FeeItem(label: 'Tuition', amount: 15000, category: FeeCategory.tuition);

void main() {
  late MockPaymentRepository repository;

  setUpAll(() {
    registerFallbackValue(EducationLevel.highSchool);
    registerFallbackValue(<FeeItem>[]);
  });

  setUp(() {
    repository = MockPaymentRepository();
  });

  group('SaveFeeStructureUseCase', () {
    test('refuses a schedule with no fees on it', () async {
      final result = await SaveFeeStructureUseCase(repository)(
        name: 'Grade 10',
        educationLevel: EducationLevel.highSchool,
        schoolYear: '2026-2027',
        items: const [],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.saveFeeStructure(
            structureId: any(named: 'structureId'),
            name: any(named: 'name'),
            educationLevel: any(named: 'educationLevel'),
            gradeLevel: any(named: 'gradeLevel'),
            schoolYear: any(named: 'schoolYear'),
            items: any(named: 'items'),
            isActive: any(named: 'isActive'),
          ));
    });

    test('refuses a zero-cost line and names it', () async {
      final result = await SaveFeeStructureUseCase(repository)(
        name: 'Grade 10',
        educationLevel: EducationLevel.highSchool,
        schoolYear: '2026-2027',
        items: const [_tuition, FeeItem(label: 'Laboratory Fee', amount: 0)],
      );
      final failure = (result as Error).failure;
      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        contains('Laboratory Fee'),
        reason: 'the message has to say which line to go and look at',
      );
    });

    // Two identical labels print as two identical rows on the family's
    // assessment, which is indistinguishable from being charged twice.
    test('refuses two fees with the same name', () async {
      final result = await SaveFeeStructureUseCase(repository)(
        name: 'Grade 10',
        educationLevel: EducationLevel.highSchool,
        schoolYear: '2026-2027',
        items: const [
          FeeItem(label: 'Books', amount: 1200),
          FeeItem(label: '  books ', amount: 1200),
        ],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('passes a valid schedule through, trimmed', () async {
      when(() => repository.saveFeeStructure(
            structureId: any(named: 'structureId'),
            name: any(named: 'name'),
            educationLevel: any(named: 'educationLevel'),
            gradeLevel: any(named: 'gradeLevel'),
            schoolYear: any(named: 'schoolYear'),
            items: any(named: 'items'),
            isActive: any(named: 'isActive'),
          )).thenAnswer((_) async => const Success(null));

      final result = await SaveFeeStructureUseCase(repository)(
        name: '  Grade 10 - Full Year  ',
        educationLevel: EducationLevel.highSchool,
        gradeLevel: 'Grade 10',
        schoolYear: ' 2026-2027 ',
        items: const [_tuition],
      );

      expect(result, isA<Success<void>>());
      verify(() => repository.saveFeeStructure(
            structureId: null,
            name: 'Grade 10 - Full Year',
            educationLevel: EducationLevel.highSchool,
            gradeLevel: 'Grade 10',
            schoolYear: '2026-2027',
            items: any(named: 'items'),
            isActive: true,
          )).called(1);
    });
  });

  group('AssessStudentFeesUseCase', () {
    test('refuses an assessment with nothing on it', () async {
      final result = await AssessStudentFeesUseCase(repository)(
        studentId: 'stu_001',
        schoolYear: '2026-2027',
        items: const [],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('refuses a missing student', () async {
      final result = await AssessStudentFeesUseCase(repository)(
        studentId: '   ',
        schoolYear: '2026-2027',
        items: const [_tuition],
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    // Blank remarks reach the server as null rather than as an empty
    // string, so nothing prints an empty remarks line on the assessment.
    test('sends blank remarks as null', () async {
      when(() => repository.assessStudentFees(
            studentId: any(named: 'studentId'),
            schoolYear: any(named: 'schoolYear'),
            items: any(named: 'items'),
            installments: any(named: 'installments'),
            discounts: any(named: 'discounts'),
            sourceStructureId: any(named: 'sourceStructureId'),
            sourceStructureName: any(named: 'sourceStructureName'),
            remarks: any(named: 'remarks'),
          )).thenAnswer((_) async => const Success(
            AssessmentOutcome(assessmentId: 'a1', total: 15000, newBalance: 15000),
          ));

      await AssessStudentFeesUseCase(repository)(
        studentId: 'stu_001',
        schoolYear: '2026-2027',
        items: const [_tuition],
        remarks: '   ',
      );

      verify(() => repository.assessStudentFees(
            studentId: 'stu_001',
            schoolYear: '2026-2027',
            items: any(named: 'items'),
            installments: any(named: 'installments'),
            discounts: any(named: 'discounts'),
            sourceStructureId: null,
            sourceStructureName: null,
            remarks: null,
          )).called(1);
    });
  });

  group('VoidAssessmentUseCase', () {
    test('refuses a reversal with no reason', () async {
      final result = await VoidAssessmentUseCase(repository)(
        assessmentId: 'a1',
        reason: '  ',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.voidAssessment(
            assessmentId: any(named: 'assessmentId'),
            reason: any(named: 'reason'),
          ));
    });
  });

  group('FeeStructure.appliesTo', () {
    FeeStructure structureFor({required EducationLevel level, String? gradeLevel}) => FeeStructure(
          id: 'fee_1',
          name: 'Schedule',
          educationLevel: level,
          gradeLevel: gradeLevel,
          schoolYear: '2026-2027',
          items: const [_tuition],
          updatedAt: DateTime(2026, 6, 1),
          updatedByName: 'Admin',
        );

    test('a schedule with no grade level covers its whole division', () {
      final structure = structureFor(level: EducationLevel.highSchool);
      expect(
        structure.appliesTo(level: EducationLevel.highSchool, studentGradeLevel: 'Grade 7'),
        isTrue,
      );
      expect(
        structure.appliesTo(level: EducationLevel.seniorHigh, studentGradeLevel: 'Grade 11'),
        isFalse,
      );
    });

    test('a grade-specific schedule matches only that grade, ignoring case', () {
      final structure = structureFor(level: EducationLevel.highSchool, gradeLevel: 'Grade 10');
      expect(
        structure.appliesTo(level: EducationLevel.highSchool, studentGradeLevel: ' grade 10 '),
        isTrue,
      );
      expect(
        structure.appliesTo(level: EducationLevel.highSchool, studentGradeLevel: 'Grade 9'),
        isFalse,
      );
    });
  });

  group('Assessment', () {
    Assessment assessment({DateTime? voidedAt}) => Assessment(
          id: 'a1',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          schoolYear: '2026-2027',
          items: const [_tuition, FeeItem(label: 'Books', amount: 2000)],
          assessedByName: 'Registrar',
          assessedAt: DateTime(2026, 6, 15),
          voidedAt: voidedAt,
        );

    test('totals its items', () {
      expect(assessment().total, 17000);
    });

    // A voided assessment still shows its own total on screen -- struck
    // through -- but must contribute nothing to the balance arithmetic,
    // or the breakdown would claim money the student does not owe.
    test('a voided assessment contributes nothing', () {
      final voided = assessment(voidedAt: DateTime(2026, 7, 1));
      expect(voided.total, 17000);
      expect(voided.effectiveTotal, 0);
      expect(voided.isVoided, isTrue);
    });
  });
}
