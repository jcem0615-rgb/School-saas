import '../../../../core/errors/result.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/coursework_submission.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../data/datasources/student_remote_datasource.dart';
import '../../data/repositories_impl/student_repository_impl.dart';
import '../../domain/repositories/student_repository.dart';
import '../../domain/usecases/student_usecases.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final studentRemoteDataSourceProvider = Provider<StudentRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('StudentRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return StudentRemoteDataSource(firestore: ref.watch(firestoreProvider), schoolId: user.schoolId!, uid: user.uid);
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepositoryImpl(ref.watch(studentRemoteDataSourceProvider));
});

/// The signed-in student's own academic record. Every other provider on
/// this page depends on this resolving first (for studentId/section), so
/// screens should branch on this being null (no linked academic record
/// yet -- possible if a Registrar created the portal login before/without
/// a full registration flow) before rendering the rest of the dashboard.
final myStudentRecordProvider = StreamProvider.autoDispose<StudentSummary?>((ref) {
  return WatchMyStudentRecordUseCase(ref.watch(studentRepositoryProvider))();
});

final mySubjectsProvider = StreamProvider.autoDispose.family<List<TeacherAssignment>, String>((ref, section) {
  return WatchMySubjectsUseCase(ref.watch(studentRepositoryProvider))(section);
});

class CourseworkQuery {
  final String section;
  final CourseworkType? typeFilter;
  const CourseworkQuery({required this.section, this.typeFilter});

  @override
  bool operator ==(Object other) =>
      other is CourseworkQuery && other.section == section && other.typeFilter == typeFilter;

  @override
  int get hashCode => Object.hash(section, typeFilter);
}

final myCourseworkProvider =
    StreamProvider.autoDispose.family<List<CourseworkItem>, CourseworkQuery>((ref, query) {
  return WatchMyCourseworkUseCase(ref.watch(studentRepositoryProvider))(query.section, typeFilter: query.typeFilter);
});

final myGradesProvider = StreamProvider.autoDispose.family<List<Grade>, String>((ref, studentId) {
  return WatchMyGradesUseCase(ref.watch(studentRepositoryProvider))(studentId);
});

final mySubmissionsProvider =
    StreamProvider.autoDispose.family<List<CourseworkSubmission>, String>((ref, studentId) {
  return WatchMySubmissionsUseCase(ref.watch(studentRepositoryProvider))(studentId);
});

/// Handing work in. Separate from the read providers because it is the
/// one thing on this screen that writes, and the screen has to be able
/// to show it failing.
class StudentActionController extends StateNotifier<AsyncValue<void>> {
  final SubmitCourseworkUseCase _submitCoursework;

  StudentActionController({required SubmitCourseworkUseCase submitCoursework})
      : _submitCoursework = submitCoursework,
        super(const AsyncData(null));

  Future<bool> submitCoursework({
    String? submissionId,
    required CourseworkItem item,
    required String studentId,
    required String studentName,
    required String section,
    required String answer,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    // `mounted` guards: this controller is autoDispose and the repository
    // it depends on rebuilds when authStateProvider emits. If that lands
    // mid-write the notifier is gone by the time the result returns, and
    // assigning state then throws -- which the user sees as a Submit
    // button that silently does nothing even though the write worked.
    if (mounted) state = const AsyncLoading();
    final result = await _submitCoursework(
      submissionId: submissionId,
      item: item,
      studentId: studentId,
      studentName: studentName,
      section: section,
      answer: answer,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
    );
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final studentActionControllerProvider =
    StateNotifierProvider.autoDispose<StudentActionController, AsyncValue<void>>((ref) {
  return StudentActionController(
    submitCoursework: SubmitCourseworkUseCase(ref.watch(studentRepositoryProvider)),
  );
});
