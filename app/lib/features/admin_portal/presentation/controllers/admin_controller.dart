import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/repositories_impl/admin_repository_impl.dart';
import '../../domain/entities/employee_summary.dart';
import '../../domain/entities/program.dart';
import '../../domain/entities/school_branding.dart';
import '../../domain/entities/teacher_assignment.dart';
import '../../domain/repositories/admin_repository.dart';
import '../../domain/usecases/employee_usecases.dart';
import '../../domain/usecases/branding_usecases.dart';
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
/// The school's logo and name.
///
/// Watched by the e-ID and the app shell as well as the admin screen, so
/// it deliberately does not sit behind an admin-only guard -- every role
/// needs to render the logo on their own ID.
final brandingProvider = StreamProvider<SchoolBranding>((ref) {
  return ref.watch(adminRepositoryProvider).watchBranding();
});

class AdminActionController extends StateNotifier<AsyncValue<CreateEmployeeOutcome?>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final CreateEmployeeUseCase _createEmployee;
  final UpdateEmployeeInfoUseCase _updateEmployeeInfo;
  final SetUserStatusUseCase _setUserStatus;
  final ResetUserPasswordUseCase _resetUserPassword;
  final CreateTeacherAssignmentUseCase _createTeacherAssignment;
  final UpdateTeacherAssignmentUseCase _updateTeacherAssignment;
  final DeleteTeacherAssignmentUseCase _deleteTeacherAssignment;
  final CreateProgramUseCase _createProgram;
  final UpdateProgramUseCase _updateProgram;
  final DeleteProgramUseCase _deleteProgram;
  final UpdateBrandingUseCase _updateBranding;

  AdminActionController({
    required CreateEmployeeUseCase createEmployee,
    required UpdateEmployeeInfoUseCase updateEmployeeInfo,
    required SetUserStatusUseCase setUserStatus,
    required ResetUserPasswordUseCase resetUserPassword,
    required CreateTeacherAssignmentUseCase createTeacherAssignment,
    required UpdateTeacherAssignmentUseCase updateTeacherAssignment,
    required DeleteTeacherAssignmentUseCase deleteTeacherAssignment,
    required CreateProgramUseCase createProgram,
    required UpdateProgramUseCase updateProgram,
    required DeleteProgramUseCase deleteProgram,
    required UpdateBrandingUseCase updateBranding,
  })  : _createEmployee = createEmployee,
        _updateEmployeeInfo = updateEmployeeInfo,
        _setUserStatus = setUserStatus,
        _resetUserPassword = resetUserPassword,
        _createTeacherAssignment = createTeacherAssignment,
        _updateTeacherAssignment = updateTeacherAssignment,
        _deleteTeacherAssignment = deleteTeacherAssignment,
        _createProgram = createProgram,
        _updateProgram = updateProgram,
        _deleteProgram = deleteProgram,
        _updateBranding = updateBranding,
        super(const AsyncData(null));

  Future<void> createEmployee({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _createEmployee(
      role: role,
      firstName: firstName,
      lastName: lastName,
      email: email,
      employeeInfo: employeeInfo,
    );
    if (mounted) state = switch (result) {
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

  Future<bool> updateTeacherAssignment({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) async {
    final result = await _updateTeacherAssignment(
      assignmentId: assignmentId,
      teacherId: teacherId,
      teacherName: teacherName,
      subject: subject,
      section: section,
      schoolYear: schoolYear,
    );
    return result.isSuccess;
  }

  Future<bool> deleteTeacherAssignment(String assignmentId) async {
    final result = await _deleteTeacherAssignment(assignmentId);
    return result.isSuccess;
  }

  Future<bool> updateProgram({
    required String programId,
    required String name,
    required String code,
    required String department,
  }) async {
    final result = await _updateProgram(
      programId: programId,
      name: name,
      code: code,
      department: department,
    );
    return result.isSuccess;
  }

  Future<bool> deleteProgram(String programId) async {
    final result = await _deleteProgram(programId);
    return result.isSuccess;
  }

  Future<bool> updateBranding({
    String? logoUrl,
    String? logoFileName,
    String? schoolName,
    String? addressLine,
  }) async {
    final result = await _updateBranding(
      logoUrl: logoUrl,
      logoFileName: logoFileName,
      schoolName: schoolName,
      addressLine: addressLine,
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
    updateTeacherAssignment: UpdateTeacherAssignmentUseCase(repo),
    deleteTeacherAssignment: DeleteTeacherAssignmentUseCase(repo),
    createProgram: CreateProgramUseCase(repo),
    updateProgram: UpdateProgramUseCase(repo),
    deleteProgram: DeleteProgramUseCase(repo),
    updateBranding: UpdateBrandingUseCase(repo),
  );
});
