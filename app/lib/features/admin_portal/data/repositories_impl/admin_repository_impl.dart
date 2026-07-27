import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/employee_summary.dart';
import '../../domain/entities/program.dart';
import '../../domain/entities/teacher_assignment.dart';
import '../../domain/repositories/admin_repository.dart';
import '../datasources/admin_remote_datasource.dart';

class AdminRepositoryImpl implements AdminRepository {
  final AdminRemoteDataSource _remote;
  const AdminRepositoryImpl(this._remote);

  Map<String, dynamic> _employeeInfoToMap(EmployeeInfo info) => {
        'department': info.department,
        'position': info.position,
        'dateHired': info.dateHired.toIso8601String(),
        'assignedDivision': info.assignedDivision?.value,
        'assignedDepartment': info.assignedDepartment,
      };

  @override
  Stream<List<EmployeeSummary>> watchEmployees() => _remote.watchEmployees();

  @override
  Future<Result<CreateEmployeeOutcome>> createEmployee({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  }) async {
    try {
      final data = await _remote.createEmployee(
        role: role.value,
        firstName: firstName,
        lastName: lastName,
        email: email,
        employeeInfo: employeeInfo == null ? null : _employeeInfoToMap(employeeInfo),
      );
      return Success(CreateEmployeeOutcome(
        uid: data['uid'] as String,
        tempPassword: data['tempPassword'] as String,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> updateEmployeeInfo({required String uid, required EmployeeInfo employeeInfo}) async {
    try {
      await _remote.updateEmployeeInfo(uid: uid, employeeInfo: _employeeInfoToMap(employeeInfo));
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> setUserStatus({required String uid, required bool active}) async {
    try {
      await _remote.setUserStatus(uid: uid, active: active);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<String>> resetUserPassword(String uid) async {
    try {
      final link = await _remote.resetUserPassword(uid);
      return Success(link);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<TeacherAssignment>> watchTeacherAssignments() => _remote.watchTeacherAssignments();

  @override
  Future<Result<void>> createTeacherAssignment({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) async {
    try {
      await _remote.createTeacherAssignment(
        teacherId: teacherId,
        teacherName: teacherName,
        subject: subject,
        section: section,
        schoolYear: schoolYear,
      );
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<Program>> watchPrograms() => _remote.watchPrograms();

  @override
  Future<Result<void>> createProgram({required String name, required String code, required String department}) async {
    try {
      await _remote.createProgram(name: name, code: code, department: department);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
