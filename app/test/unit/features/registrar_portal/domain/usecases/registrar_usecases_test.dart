import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/registrar_portal/domain/repositories/registrar_repository.dart';
import 'package:logicclass/features/registrar_portal/domain/usecases/student_usecases.dart';

class MockRegistrarRepository extends Mock implements RegistrarRepository {}

/// Registration requires a birthday, so every valid-path call here
/// carries one. Kept as one constant rather than inline dates so a test
/// that is about something else does not read like it is about ages.
final birthday = DateTime(2010, 3, 14);

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
        birthDate: birthday,
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
        birthDate: birthday,
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
            birthDate: birthday,
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
        birthDate: birthday,
      );

      expect(result, isA<Success<RegisterStudentOutcome>>());
    });
  });

  group('RegisterStudentUseCase - birthday', () {
    // Required at registration because it is printed on the ID card, and
    // chasing it down afterwards is what left records without one.
    test('rejects a registration with no birthday', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.elementary,
        gradeLevel: 'Grade 7',
        section: 'A',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a birthday in the future', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        educationLevel: EducationLevel.elementary,
        gradeLevel: 'Grade 7',
        section: 'A',
        birthDate: DateTime.now().add(const Duration(days: 1)),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
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
        birthDate: birthday,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
      verifyNever(() => repository.registerStudent(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            middleName: any(named: 'middleName'),
            educationLevel: any(named: 'educationLevel'),
            gradeLevel: any(named: 'gradeLevel'),
            section: any(named: 'section'),
            birthDate: any(named: 'birthDate'),
            programId: any(named: 'programId'),
            guardianContacts: any(named: 'guardianContacts'),
          ));
    });

    test('rejects a strand or program set for a division that has neither', () async {
      final useCase = RegisterStudentUseCase(repository);
      for (final level in [EducationLevel.elementary, EducationLevel.highSchool]) {
        final result = await useCase(
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          educationLevel: level,
          gradeLevel: 'Grade 9',
          section: 'A',
          birthDate: birthday,
          programId: 'program_1',
        );
        expect((result as Error).failure, isA<ValidationFailure>(),
            reason: '${level.displayLabel} students do not enrol in anything');
      }
    });

    // Senior High is the second division with a catalogue: Grades 11-12
    // pick a DepEd strand, exactly as a college student picks a degree.
    test('rejects a Senior High student with no strand selected', () async {
      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Trisha',
        lastName: 'Mercado',
        educationLevel: EducationLevel.seniorHigh,
        gradeLevel: 'Grade 11',
        section: 'STEM 11-A',
        birthDate: birthday,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('accepts a Senior High student with a strand', () async {
      when(() => repository.registerStudent(
            firstName: 'Trisha',
            lastName: 'Mercado',
            middleName: null,
            educationLevel: EducationLevel.seniorHigh,
            gradeLevel: 'Grade 11',
            section: 'STEM 11-A',
            birthDate: birthday,
            programId: 'shs_stem',
            guardianContacts: const [],
          )).thenAnswer(
        (_) async => const Success(RegisterStudentOutcome(studentId: 's3', studentNumber: 'S-2026-000003')),
      );

      final useCase = RegisterStudentUseCase(repository);
      final result = await useCase(
        firstName: 'Trisha',
        lastName: 'Mercado',
        educationLevel: EducationLevel.seniorHigh,
        gradeLevel: 'Grade 11',
        section: 'STEM 11-A',
        birthDate: birthday,
        programId: 'shs_stem',
      );

      expect(result, isA<Success<RegisterStudentOutcome>>());
    });

    test('accepts a college student with a program and passes it through', () async {
      when(() => repository.registerStudent(
            firstName: 'Maria',
            lastName: 'Santos',
            middleName: null,
            educationLevel: EducationLevel.college,
            gradeLevel: '1st Year',
            section: 'A',
            birthDate: birthday,
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
        birthDate: birthday,
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
            birthDate: birthday,
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
