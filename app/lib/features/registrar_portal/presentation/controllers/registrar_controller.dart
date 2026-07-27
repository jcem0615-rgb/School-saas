import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/registrar_remote_datasource.dart';
import '../../data/repositories_impl/registrar_repository_impl.dart';
import '../../domain/entities/student_summary.dart';
import '../../domain/repositories/registrar_repository.dart';
import '../../domain/usecases/student_usecases.dart';

final registrarRemoteDataSourceProvider = Provider<RegistrarRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('RegistrarRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return RegistrarRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingRegistrar(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final registrarRepositoryProvider = Provider<RegistrarRepository>((ref) {
  return RegistrarRepositoryImpl(ref.watch(registrarRemoteDataSourceProvider));
});

final studentsStreamProvider = StreamProvider.autoDispose<List<StudentSummary>>((ref) {
  return WatchStudentsUseCase(ref.watch(registrarRepositoryProvider))();
});

class RegistrarActionController extends StateNotifier<AsyncValue<void>> {
  final RegisterStudentUseCase _registerStudent;
  final UpdateStudentUseCase _updateStudent;
  final ProvisionStudentAccountUseCase _provisionStudentAccount;

  RegistrarActionController({
    required RegisterStudentUseCase registerStudent,
    required UpdateStudentUseCase updateStudent,
    required ProvisionStudentAccountUseCase provisionStudentAccount,
  })  : _registerStudent = registerStudent,
        _updateStudent = updateStudent,
        _provisionStudentAccount = provisionStudentAccount,
        super(const AsyncData(null));

  Future<RegisterStudentOutcome?> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    List<GuardianContact> guardianContacts = const [],
  }) async {
    state = const AsyncLoading();
    final result = await _registerStudent(
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      section: section,
      programId: programId,
      guardianContacts: guardianContacts,
    );
    if (result case Success(:final value)) {
      state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      state = AsyncError(failure.message, StackTrace.current);
    }
    return null;
  }

  Future<bool> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
  }) async {
    state = const AsyncLoading();
    final result = await _updateStudent(
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      gradeLevel: gradeLevel,
      section: section,
      status: status,
    );
    if (result case Success()) {
      state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }

  Future<ProvisionStudentAccountOutcome?> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    state = const AsyncLoading();
    final result = await _provisionStudentAccount(
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      email: email,
    );
    if (result case Success(:final value)) {
      state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      state = AsyncError(failure.message, StackTrace.current);
    }
    return null;
  }
}

final registrarActionControllerProvider =
    StateNotifierProvider.autoDispose<RegistrarActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(registrarRepositoryProvider);
  return RegistrarActionController(
    registerStudent: RegisterStudentUseCase(repo),
    updateStudent: UpdateStudentUseCase(repo),
    provisionStudentAccount: ProvisionStudentAccountUseCase(repo),
  );
});
