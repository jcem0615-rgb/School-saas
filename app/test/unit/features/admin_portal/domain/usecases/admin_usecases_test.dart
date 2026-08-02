import 'package:school_saas/core/constants/education_level.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/core/errors/failures.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/admin_portal/domain/entities/employee_summary.dart';
import 'package:school_saas/features/admin_portal/domain/repositories/admin_repository.dart';
import 'package:school_saas/features/admin_portal/domain/usecases/employee_usecases.dart';
import 'package:school_saas/features/admin_portal/domain/usecases/program_usecases.dart';
import 'package:school_saas/features/admin_portal/domain/usecases/teacher_assignment_usecases.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late MockAdminRepository repository;

  setUp(() {
    repository = MockAdminRepository();
  });

  group('CreateEmployeeUseCase', () {
    test('rejects an invalid email', () async {
      final useCase = CreateEmployeeUseCase(repository);
      final result = await useCase(
        role: UserRole.faculty,
        firstName: 'Ana',
        lastName: 'Reyes',
        email: 'not-an-email',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty first or last name', () async {
      final useCase = CreateEmployeeUseCase(repository);
      final result = await useCase(
        role: UserRole.faculty,
        firstName: '',
        lastName: 'Reyes',
        email: 'ana@school.edu.ph',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('delegates to the repository on valid input', () async {
      when(() => repository.createEmployee(
            role: UserRole.faculty,
            firstName: 'Ana',
            lastName: 'Reyes',
            email: 'ana@school.edu.ph',
            employeeInfo: null,
          )).thenAnswer((_) async => const Success(
            CreateEmployeeOutcome(uid: 'uid_1', tempPassword: 'Temp1234'),
          ));

      final useCase = CreateEmployeeUseCase(repository);
      final result = await useCase(
        role: UserRole.faculty,
        firstName: 'Ana',
        lastName: 'Reyes',
        email: 'ana@school.edu.ph',
      );

      expect(result, isA<Success<CreateEmployeeOutcome>>());
    });
  });

  group('UpdateEmployeeInfoUseCase', () {
    test('rejects an empty department', () async {
      final useCase = UpdateEmployeeInfoUseCase(repository);
      final result = await useCase(
        uid: 'uid_1',
        employeeInfo: EmployeeInfo(department: '', position: 'Teacher', dateHired: DateTime.now()),
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('CreateTeacherAssignmentUseCase', () {
    test('rejects a missing teacher', () async {
      final useCase = CreateTeacherAssignmentUseCase(repository);
      final result = await useCase(
        teacherId: '',
        teacherName: '',
        subject: 'Math',
        section: 'Grade 7 - A',
        schoolYear: '2026-2027',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects a missing subject or section', () async {
      final useCase = CreateTeacherAssignmentUseCase(repository);
      final result = await useCase(
        teacherId: 'teacher_1',
        teacherName: 'Mr. Cruz',
        subject: '',
        section: '',
        schoolYear: '2026-2027',
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });
  });

  group('CreateProgramUseCase', () {
    test('rejects an empty program name', () async {
      final useCase = CreateProgramUseCase(repository);
      final result = await useCase(
        name: '',
        code: 'BSCS',
        department: 'College of Engineering',
        educationLevel: EducationLevel.college,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty department', () async {
      final useCase = CreateProgramUseCase(repository);
      final result = await useCase(
        name: 'BS Computer Science',
        code: 'BSCS',
        department: '',
        educationLevel: EducationLevel.college,
      );
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    // Elementary and Junior High students never reference the catalogue,
    // so an entry filed under one of them could never be selected -- it
    // would sit in the list forever looking like unfinished configuration.
    test('rejects a catalogue entry for a division that has no catalogue', () async {
      final useCase = CreateProgramUseCase(repository);
      for (final level in [EducationLevel.elementary, EducationLevel.highSchool]) {
        final result = await useCase(
          name: 'Something',
          code: 'X',
          department: 'Y',
          educationLevel: level,
        );
        expect((result as Error).failure, isA<ValidationFailure>(),
            reason: '${level.displayLabel} has no catalogue');
      }
    });

    test('delegates a valid program to the repository', () async {
      when(() => repository.createProgram(
            name: 'BS Computer Science',
            code: 'BSCS',
            department: 'College of Engineering',
            educationLevel: EducationLevel.college,
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateProgramUseCase(repository);
      final result = await useCase(
        name: 'BS Computer Science',
        code: 'BSCS',
        department: 'College of Engineering',
        educationLevel: EducationLevel.college,
      );

      expect(result, isA<Success<void>>());
    });

    test('delegates a Senior High strand to the repository', () async {
      when(() => repository.createProgram(
            name: 'Science, Technology, Engineering and Mathematics',
            code: 'STEM',
            department: 'Academic',
            educationLevel: EducationLevel.seniorHigh,
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateProgramUseCase(repository);
      final result = await useCase(
        name: 'Science, Technology, Engineering and Mathematics',
        code: 'STEM',
        department: 'Academic',
        educationLevel: EducationLevel.seniorHigh,
      );

      expect(result, isA<Success<void>>());
    });
  });
}
