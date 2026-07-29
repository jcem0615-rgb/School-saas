import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/constants/education_level.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:school_saas/features/registrar_portal/domain/repositories/registrar_repository.dart';
import 'package:school_saas/features/registrar_portal/domain/usecases/student_usecases.dart';

class MockRegistrarRepository extends Mock implements RegistrarRepository {}

void main() {
  late MockRegistrarRepository repository;

  // Required before `any(named:)` can match the non-nullable
  // educationLevel and guardianContacts parameters on registerStudent.
  setUpAll(() {
    registerFallbackValue(EducationLevel.elementary);
    registerFallbackValue(const <GuardianContact>[]);
  });

  setUp(() {
    repository = MockRegistrarRepository();
  });

  group('RegisterStudentUseCase - basic fields', () {
    test('rejects an empty grade level', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.elementary,
        gradeLevel: '',
        section: 'A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty section', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.elementary,
        gradeLevel: 'Grade 7',
        section: '',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('delegates to the repository on valid elementary input (no program)', () async {
      when(() => repository.registerStudent(
            firstName: 'Juan',
            lastName: 'Dela Cruz',
            middleName: null,
            educationLevel: EducationLevel.elementary,
            gradeLevel: 'Grade 7',
            section: 'A',
            programId: null,
            guardianContacts: const [],
          )).thenAnswer(
        (_) async => const Success(RegisterStudentOutcome(studentId: 's1', studentNumber: 'S-2026-000001')),
      );

      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.elementary,
        gradeLevel: 'Grade 7',
        section: 'A',
      );

      expect(result, isA<Success<RegisterStudentOutcome>>());
    });
  });

  group('RegisterStudentUseCase - division/program rules', () {
    test('rejects a college student with no program selected', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Maria',
        lastName: 'Santos',
        educationLevel: EducationLevel.college,
        gradeLevel: '1st Year',
        section: 'A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.registerStudent(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            middleName: any(named: 'middleName'),
            educationLevel: any(named: 'educationLevel'),
            gradeLevel: any(named: 'gradeLevel'),
            section: any(named: 'section'),
            programId: any(named: 'programId'),
            guardianContacts: any(named: 'guardianContacts'),
          ));
    });

    test('rejects a program set for a non-college student', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.highSchool,
        gradeLevel: 'Grade 11',
        section: 'A',
        programId: 'program_1',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('accepts a college student with a program and passes it through', () async {
      when(() => repository.registerStudent(
            firstName: 'Maria',
            lastName: 'Santos',
            middleName: null,
            educationLevel: EducationLevel.college,
            gradeLevel: '1st Year',
            section: 'A',
            programId: 'program_1',
            guardianContacts: const [],
          )).thenAnswer(
        (_) async => const Success(RegisterStudentOutcome(studentId: 's2', studentNumber: 'S-2026-000002')),
      );

      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Maria',
        lastName: 'Santos',
        educationLevel: EducationLevel.college,
        gradeLevel: '1st Year',
        section: 'A',
        programId: 'program_1',
      );

      expect(result, isA<Success<RegisterStudentOutcome>>());
      verify(() => repository.registerStudent(
            firstName: 'Maria',
            lastName: 'Santos',
            middleName: null,
            educationLevel: EducationLevel.college,
            gradeLevel: '1st Year',
            section: 'A',
            programId: 'program_1',
            guardianContacts: const [],
          )).called(1);
    });
  });

  group('ProvisionStudentAccountUseCase', () {
    test('rejects an invalid email', () async {
      final useCase = ProvisionStudentAccountUseCase(repository);
      final result = await useCase(
        studentId: 's1',
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        email: 'not-an-email',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });
}
