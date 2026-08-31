import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/faculty_remote_datasource.dart';
import '../../data/repositories_impl/faculty_repository_impl.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/answer_key.dart';
import '../../domain/entities/coursework_submission.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/grade.dart';
import '../../domain/entities/grading_scheme.dart';
import '../../domain/entities/quarterly_grade.dart';
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

  /// Answer keys and per-submission marks go straight to the repository:
  /// the validation that would live in a use case (a non-empty key, marks
  /// above zero, a score within range) belongs to the screens that
  /// collect it, and inventing a use case per field would be ceremony.
  final FacultyRepository _repository;

  FacultyActionController({
    required CreateCourseworkItemUseCase createCourseworkItem,
    required UpdateCourseworkItemUseCase updateCourseworkItem,
    required DeleteCourseworkItemUseCase deleteCourseworkItem,
    required SubmitGradeUseCase submitGrade,
    required FacultyRepository repository,
  })  : _createCourseworkItem = createCourseworkItem,
        _updateCourseworkItem = updateCourseworkItem,
        _deleteCourseworkItem = deleteCourseworkItem,
        _submitGrade = submitGrade,
        _repository = repository,
        super(const AsyncData(null));

  Future<bool> createCourseworkItem({
    required CourseworkType type,
    required CourseworkDelivery delivery,
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
      delivery: delivery,
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
    required CourseworkDelivery delivery,
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
      delivery: delivery,
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

  /// Saving the scheme and confirming it are two acts, not one.
  ///
  /// A screen that saved and confirmed together would make the
  /// confirmation meaningless -- it would record that somebody typed
  /// numbers, which is not the same as somebody having checked them
  /// against the order that is current for their school.
  Future<bool> saveGradingScheme(GradingScheme scheme) =>
      _run(() => SaveGradingSchemeUseCase(_repository)(scheme));

  Future<bool> confirmGradingScheme(GradingScheme scheme) =>
      _run(() => ConfirmGradingSchemeUseCase(_repository)(scheme));

  Future<bool> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    required GradingComponent component,
    String? courseworkItemId,
    String? remarks,
  }) => _run(() => _submitGrade(
        component: component,
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

  Future<bool> saveAnswerKey({
    required String courseworkId,
    required List<String> answers,
    required double pointsPerQuestion,
  }) =>
      _run(() => _repository.saveAnswerKey(
            courseworkId: courseworkId,
            answers: answers,
            pointsPerQuestion: pointsPerQuestion,
          ));

  Future<bool> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) =>
      _run(() => _repository.gradeSubmission(
            submissionId: submissionId,
            score: score,
            feedback: feedback,
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
    repository: repo,
  );
});

final answerKeyProvider =
    StreamProvider.autoDispose.family<AnswerKey?, String>((ref, courseworkId) {
  return ref.watch(facultyRepositoryProvider).watchAnswerKey(courseworkId);
});

final submissionsForProvider =
    StreamProvider.autoDispose.family<List<CourseworkSubmission>, String>((ref, courseworkId) {
  return ref.watch(facultyRepositoryProvider).watchSubmissionsFor(courseworkId);
});

/// The school's grading scheme.
///
/// Not autoDispose: every screen that shows a computed grade needs it, and
/// a report card printed the instant a screen opens must not come out
/// against a scheme that has not arrived yet.
final gradingSchemeProvider = StreamProvider<GradingScheme>((ref) {
  return WatchGradingSchemeUseCase(ref.watch(facultyRepositoryProvider))();
});

/// One section's marks in one subject, turned into a quarterly grade per
/// student, for the teacher's own class record.
final sectionQuarterlyGradesProvider = Provider.autoDispose
    .family<Map<String, QuarterlyGrade>, GradeQuery>((ref, query) {
  final grades = ref.watch(gradesStreamProvider(query)).valueOrNull ?? const <Grade>[];
  final scheme = ref.watch(gradingSchemeProvider).valueOrNull;
  if (scheme == null) return const {};

  final byStudent = <String, List<Grade>>{};
  for (final grade in grades) {
    (byStudent[grade.studentId] ??= []).add(grade);
  }
  return {
    for (final entry in byStudent.entries)
      entry.key: computeQuarterlyGrade(
        subject: query.subject,
        // Every mark on this screen is for the term the teacher is
        // looking at; the first one's term names it.
        term: entry.value.first.term,
        grades: entry.value,
        scheme: scheme,
      ),
  };
});
