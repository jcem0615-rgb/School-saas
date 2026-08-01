import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/faculty_remote_datasource.dart';
import '../../data/repositories_impl/faculty_repository_impl.dart';
import '../../domain/entities/coursework_item.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/grade.dart';
import '../../domain/repositories/faculty_repository.dart';
import '../../domain/usecases/coursework_usecases.dart';
import '../../domain/usecases/grade_usecases.dart';

final facultyRemoteDataSourceProvider = Provider<FacultyRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('FacultyRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return FacultyRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingFaculty(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final facultyRepositoryProvider = Provider<FacultyRepository>((ref) {
  return FacultyRepositoryImpl(ref.watch(facultyRemoteDataSourceProvider));
});

final myCourseworkStreamProvider = StreamProvider.autoDispose<List<CourseworkItem>>((ref) {
  return WatchMyCourseworkItemsUseCase(ref.watch(facultyRepositoryProvider))();
});

class GradeQuery {
  final String subject;
  final String section;
  const GradeQuery({required this.subject, required this.section});

  @override
  bool operator ==(Object other) =>
      other is GradeQuery && other.subject == subject && other.section == section;

  @override
  int get hashCode => Object.hash(subject, section);
}

/// Roster for a section, so the grade screen can list students instead of
/// asking the teacher to recall student IDs.
final sectionRosterProvider =
    StreamProvider.autoDispose.family<List<StudentSummary>, String>((ref, section) {
  return ref.watch(facultyRepositoryProvider).watchStudentsInSection(section);
});

final gradesStreamProvider = StreamProvider.autoDispose.family<List<Grade>, GradeQuery>((ref, query) {
  return WatchGradesUseCase(ref.watch(facultyRepositoryProvider))(subject: query.subject, section: query.section);
});

class FacultyActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final CreateCourseworkItemUseCase _createCourseworkItem;
  final UpdateCourseworkItemUseCase _updateCourseworkItem;
  final DeleteCourseworkItemUseCase _deleteCourseworkItem;
  final SubmitGradeUseCase _submitGrade;

  FacultyActionController({
    required CreateCourseworkItemUseCase createCourseworkItem,
    required UpdateCourseworkItemUseCase updateCourseworkItem,
    required DeleteCourseworkItemUseCase deleteCourseworkItem,
    required SubmitGradeUseCase submitGrade,
  })  : _createCourseworkItem = createCourseworkItem,
        _updateCourseworkItem = updateCourseworkItem,
        _deleteCourseworkItem = deleteCourseworkItem,
        _submitGrade = submitGrade,
        super(const AsyncData(null));

  Future<bool> createCourseworkItem({
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    bool published = true,
    String? attachmentUrl,
    String? attachmentName,
  }) => _run(() => _createCourseworkItem(
        type: type,
        title: title,
        description: description,
        subject: subject,
        section: section,
        dueDate: dueDate,
        totalPoints: totalPoints,
        published: published,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
      ));

  Future<bool> updateCourseworkItem({
    required String itemId,
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    bool published = true,
    String? attachmentUrl,
    String? attachmentName,
  }) => _run(() => _updateCourseworkItem(
        itemId: itemId,
        type: type,
        title: title,
        description: description,
        subject: subject,
        section: section,
        dueDate: dueDate,
        totalPoints: totalPoints,
        published: published,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
      ));

  Future<bool> deleteCourseworkItem(String itemId) =>
      _run(() => _deleteCourseworkItem(itemId));

  Future<bool> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    String? courseworkItemId,
    String? remarks,
  }) => _run(() => _submitGrade(
        studentId: studentId,
        studentName: studentName,
        subject: subject,
        section: section,
        term: term,
        score: score,
        maxScore: maxScore,
        courseworkItemId: courseworkItemId,
        remarks: remarks,
      ));

  Future<bool> _run(Future<dynamic> Function() action) async {
    if (mounted) state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final facultyActionControllerProvider =
    StateNotifierProvider.autoDispose<FacultyActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(facultyRepositoryProvider);
  return FacultyActionController(
    createCourseworkItem: CreateCourseworkItemUseCase(repo),
    updateCourseworkItem: UpdateCourseworkItemUseCase(repo),
    deleteCourseworkItem: DeleteCourseworkItemUseCase(repo),
    submitGrade: SubmitGradeUseCase(repo),
  );
});
