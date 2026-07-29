import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/result.dart';
import '../entities/employee_summary.dart';
import '../entities/program.dart';
import '../entities/teacher_assignment.dart';

class CreateEmployeeOutcome {
  final String uid;
  final String tempPassword;
  const CreateEmployeeOutcome({required this.uid, required this.tempPassword});
}

abstract class AdminRepository {
  Stream<List<EmployeeSummary>> watchEmployees();

  Future<Result<CreateEmployeeOutcome>> createEmployee({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  });

  /// Updates non-security-sensitive fields directly (allowed by
  /// firestore.rules for director/admin) -- no callable needed for this one.
  Future<Result<void>> updateEmployeeInfo({required String uid, required EmployeeInfo employeeInfo});

  Future<Result<void>> setUserStatus({required String uid, required bool active});

  Future<Result<String>> resetUserPassword(String uid);

  Stream<List<TeacherAssignment>> watchTeacherAssignments();
  Future<Result<void>> createTeacherAssignment({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  });

  /// College degree programs/courses. Read by any tenant member (needed
  /// during Student Registration in Registrar Portal, and for Student
  /// Portal display); only Director/Admin manage the catalog.
  Future<Result<void>> updateTeacherAssignment({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  });

  /// Soft delete throughout -- firestore.rules denies hard delete on
  /// every collection, so these flip `isDeleted` instead.
  Future<Result<void>> deleteTeacherAssignment(String assignmentId);

  Stream<List<Program>> watchPrograms();
  Future<Result<void>> createProgram({required String name, required String code, required String department});
  Future<Result<void>> updateProgram({
    required String programId,
    required String name,
    required String code,
    required String department,
  });
  Future<Result<void>> deleteProgram(String programId);
}
