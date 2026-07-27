import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/repositories_impl/admin_repository_impl.dart';
import '../../domain/entities/employee_summary.dart';
import '../../domain/entities/program.dart';
import '../../domain/entities/teacher_assignment.dart';
import '../../domain/repositories/admin_repository.dart';
import '../../domain/usecases/employee_usecases.dart';
import '../../domain/usecases/program_usecases.dart';
import '../../domain/usecases/teacher_assignment_usecases.dart';

final adminRemoteDataSourceProvider = Provider<AdminRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('AdminRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return AdminRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingAdmin(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepositoryImpl(ref.watch(adminRemoteDataSourceProvider));
});

final employeesStreamProvider = StreamProvider.autoDispose<List<EmployeeSummary>>((ref) {
  return WatchEmployeesUseCase(ref.watch(adminRepositoryProvider))();
});

final teacherAssignmentsStreamProvider = StreamProvider.autoDispose<List<TeacherAssignment>>((ref) {
  return WatchTeacherAssignmentsUseCase(ref.watch(adminRepositoryProvider))();
});

final programsStreamProvider = StreamProvider.autoDispose<List<Program>>((ref) {
  return WatchProgramsUseCase(ref.watch(adminRepositoryProvider))();
});

/// Result of a create-employee action, surfaced once so the UI can show
/// the temporary password for hand-off (see provisionUser.ts doc comment
/// on why this is returned directly rather than only emailed).
class AdminActionController extends StateNotifier<AsyncValue<CreateEmployeeOutcome?>> {
  final CreateEmployeeUseCase _createEmployee;
  final UpdateEmployeeInfoUseCase _updateEmployeeInfo;
  final SetUserStatusUseCase _setUserStatus;
  final ResetUserPasswordUseCase _resetUserPassword;
  final CreateTeacherAssignmentUseCase _createTeacherAssignment;
  final CreateProgramUseCase _createProgram;

  AdminActionController({
    required CreateEmployeeUseCase createEmployee,
    required UpdateEmployeeInfoUseCase updateEmployeeInfo,
    required SetUserStatusUseCase setUserStatus,
    required ResetUserPasswordUseCase resetUserPassword,
    required CreateTeacherAssignmentUseCase createTeacherAssignment,
    required CreateProgramUseCase createProgram,
  })  : _createEmployee = createEmployee,
        _updateEmployeeInfo = updateEmployeeInfo,
        _setUserStatus = setUserStatus,
        _resetUserPassword = resetUserPassword,
        _createTeacherAssignment = createTeacherAssignment,
        _createProgram = createProgram,
        super(const AsyncData(null));

  Future<void> createEmployee({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  }) async {
    state = const AsyncLoading();
    final result = await _createEmployee(
      role: role,
      firstName: firstName,
      lastName: lastName,
      email: email,
      employeeInfo: employeeInfo,
    );
    state = switch (result) {
      Success(:final value) => AsyncData(value),
      Error(:final failure) => AsyncError(failure.message, StackTrace.current),
    };
  }

  Future<bool> updateEmployeeInfo({required String uid, required EmployeeInfo employeeInfo}) async {
    final result = await _updateEmployeeInfo(uid: uid, employeeInfo: employeeInfo);
    return result.isSuccess;
  }

  Future<bool> setUserStatus({required String uid, required bool active}) async {
    final result = await _setUserStatus(uid: uid, active: active);
    return result.isSuccess;
  }

  Future<String?> resetUserPassword(String uid) async {
    final result = await _resetUserPassword(uid);
    return result.valueOrNull;
  }

  Future<bool> createTeacherAssignment({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) async {
    final result = await _createTeacherAssignment(
      teacherId: teacherId,
      teacherName: teacherName,
      subject: subject,
      section: section,
      schoolYear: schoolYear,
    );
    return result.isSuccess;
  }

  void reset() => state = const AsyncData(null);

  Future<bool> createProgram({required String name, required String code, required String department}) async {
    final result = await _createProgram(name: name, code: code, department: department);
    return result.isSuccess;
  }
}

final adminActionControllerProvider =
    StateNotifierProvider.autoDispose<AdminActionController, AsyncValue<CreateEmployeeOutcome?>>((ref) {
  final repo = ref.watch(adminRepositoryProvider);
  return AdminActionController(
    createEmployee: CreateEmployeeUseCase(repo),
    updateEmployeeInfo: UpdateEmployeeInfoUseCase(repo),
    setUserStatus: SetUserStatusUseCase(repo),
    resetUserPassword: ResetUserPasswordUseCase(repo),
    createTeacherAssignment: CreateTeacherAssignmentUseCase(repo),
    createProgram: CreateProgramUseCase(repo),
  );
});
