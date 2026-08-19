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
      final result = await useCase(name: '', code: 'BSCS', department: 'College of Engineering');
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('rejects an empty department', () async {
      final useCase = CreateProgramUseCase(repository);
      final result = await useCase(name: 'BS Computer Science', code: 'BSCS', department: '');
      expect((result as Error).failure, isA<ValidationFailure>());
    });

    test('delegates a valid program to the repository', () async {
      when(() => repository.createProgram(
            name: 'BS Computer Science',
            code: 'BSCS',
            department: 'College of Engineering',
          )).thenAnswer((_) async => const Success(null));

      final useCase = CreateProgramUseCase(repository);
      final result =
          await useCase(name: 'BS Computer Science', code: 'BSCS', department: 'College of Engineering');

      expect(result, isA<Success<void>>());
    });
  });
}
