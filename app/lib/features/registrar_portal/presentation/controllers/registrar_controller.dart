import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../../core/constants/education_level.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/registrar_remote_datasource.dart';
import '../../data/repositories_impl/registrar_repository_impl.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../domain/entities/document_release.dart';
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

/// The unbounded roster. Still the right provider for the screens that
/// need every student at once -- a faculty submission sheet, a section
/// picker -- and the wrong one for the student list, which is why that
/// screen now uses [pagedStudentsStreamProvider] instead.
final studentsStreamProvider = StreamProvider.autoDispose<List<StudentSummary>>((ref) {
  return WatchStudentsUseCase(ref.watch(registrarRepositoryProvider))();
});

/// How many students one page of the student list holds.
///
/// A provider rather than a constant so demo mode can override it down to
/// something the nine seeded students actually exceed. Paging that never
/// triggers is paging you cannot check works.
final studentPageSizeProvider = Provider<int>((ref) => 20);

/// Which division the student list is filtered to, lifted out of the
/// screen's own state because the query -- not the widget -- is what has
/// to know: the filter has to reach Firestore's `where`, or a page of
/// twenty arrives and four of them are Senior High.
final studentDivisionFilterProvider = StateProvider.autoDispose<EducationLevel?>((ref) => null);

/// How many students the list has asked for so far. Load more raises it by
/// one page; changing the division resets it.
final studentPageLimitProvider = StateProvider.autoDispose<int>((ref) {
  return ref.watch(studentPageSizeProvider);
});

/// One page of the roster.
///
/// A growing `limit` rather than a `startAfter` cursor, deliberately. The
/// list is live -- a student registered on another device appears without
/// a refresh -- and a cursor chain gives you one stream per page, each
/// with its own lifetime, which is a lot of machinery to keep three pages
/// of a roster in sync. One widening query stays one stream. The cost is
/// that page three re-reads pages one and two; at twenty a page that is a
/// trade worth making against the alternative of reading all three
/// thousand every time the screen opens.
final pagedStudentsStreamProvider = StreamProvider.autoDispose<List<StudentSummary>>((ref) {
  return WatchStudentsUseCase(ref.watch(registrarRepositoryProvider))(
    limit: ref.watch(studentPageLimitProvider),
    educationLevel: ref.watch(studentDivisionFilterProvider),
  );
});

/// Every mark one student has, for building their transcript.
final studentGradesStreamProvider =
    StreamProvider.autoDispose.family<List<Grade>, String>((ref, studentId) {
  return WatchStudentGradesUseCase(ref.watch(registrarRepositoryProvider))(studentId);
});

/// What has already been handed out for one student, newest first.
final documentReleasesStreamProvider =
    StreamProvider.autoDispose.family<List<DocumentRelease>, String>((ref, studentId) {
  return WatchDocumentReleasesUseCase(ref.watch(registrarRepositoryProvider))(studentId);
});

class RegistrarActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final RegisterStudentUseCase _registerStudent;
  final UpdateStudentUseCase _updateStudent;
  final ProvisionStudentAccountUseCase _provisionStudentAccount;
  final SetStudentBalanceUseCase _setStudentBalance;
  final SetStudentPhotoUseCase _setStudentPhoto;
  final RecordDocumentReleaseUseCase _recordDocumentRelease;

  RegistrarActionController({
    required RegisterStudentUseCase registerStudent,
    required UpdateStudentUseCase updateStudent,
    required ProvisionStudentAccountUseCase provisionStudentAccount,
    required SetStudentBalanceUseCase setStudentBalance,
    required SetStudentPhotoUseCase setStudentPhoto,
    required RecordDocumentReleaseUseCase recordDocumentRelease,
  })  : _registerStudent = registerStudent,
        _updateStudent = updateStudent,
        _provisionStudentAccount = provisionStudentAccount,
        _setStudentBalance = setStudentBalance,
        _setStudentPhoto = setStudentPhoto,
        _recordDocumentRelease = recordDocumentRelease,
        super(const AsyncData(null));

  Future<bool> recordDocumentRelease({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _recordDocumentRelease(
      studentId: studentId,
      studentName: studentName,
      document: document,
      copies: copies,
      purpose: purpose,
      releasedToName: releasedToName,
      releasedToRelation: releasedToRelation,
      remarks: remarks,
    );
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<bool> setStudentPhoto({
    required String studentId,
    required String photoUrl,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _setStudentPhoto(studentId: studentId, photoUrl: photoUrl);
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<bool> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _setStudentBalance(
      studentId: studentId,
      balance: balance,
      remarks: remarks,
    );
    // `mounted` guard: this controller is autoDispose, and the demo/real
    // repositories it depends on rebuild whenever authStateProvider emits.
    // If that happens while the write is in flight the notifier is gone by
    // the time the result comes back, and assigning `state` then throws
    // "used after dispose" -- which surfaced as a balance edit that
    // silently did nothing even though the write had landed.
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<RegisterStudentOutcome?> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    List<GuardianContact> guardianContacts = const [],
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _registerStudent(
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      section: section,
      programId: programId,
      birthDate: birthDate,
      guardianContacts: guardianContacts,
    );
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
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
    DateTime? birthDate,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _updateStudent(
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      gradeLevel: gradeLevel,
      section: section,
      status: status,
      birthDate: birthDate,
    );
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }

  Future<ProvisionStudentAccountOutcome?> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _provisionStudentAccount(
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      email: email,
    );
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
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
    setStudentBalance: SetStudentBalanceUseCase(repo),
    setStudentPhoto: SetStudentPhotoUseCase(repo),
    recordDocumentRelease: RecordDocumentReleaseUseCase(repo),
  );
});
