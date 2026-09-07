import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/answer_key.dart';
import '../../domain/entities/coursework_submission.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/class_assessment.dart';
import '../../domain/entities/grade.dart';
import '../../domain/entities/grading_scheme.dart';
import '../../domain/repositories/faculty_repository.dart';
import '../datasources/faculty_remote_datasource.dart';

class FacultyRepositoryImpl implements FacultyRepository {
  final FacultyRemoteDataSource _remote;
  const FacultyRepositoryImpl(this._remote);

  /// Same try/catch shape the hand-written methods below use, factored out
  /// for the edit/delete paths that have no per-call error mapping.
  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<CourseworkItem>> watchMyCourseworkItems() => _remote.watchMyCourseworkItems();

  @override
  Stream<List<CourseworkSubmission>> watchSubmissionsFor(String courseworkId) =>
      _remote.watchSubmissionsFor(courseworkId);

  @override
  Stream<AnswerKey?> watchAnswerKey(String courseworkId) => _remote.watchAnswerKey(courseworkId);

  @override
  Future<Result<void>> saveAnswerKey({
    required String courseworkId,
    required List<String> answers,
    required double pointsPerQuestion,
  }) {
    return _run(() => _remote.saveAnswerKey(
          courseworkId: courseworkId,
          answers: answers,
          pointsPerQuestion: pointsPerQuestion,
        ));
  }

  @override
  Future<Result<void>> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) {
    return _run(() => _remote.gradeSubmission(
          submissionId: submissionId,
          score: score,
          feedback: feedback,
        ));
  }

  @override
  Future<Result<void>> createCourseworkItem({
    required CourseworkType type,
    required CourseworkDelivery delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    try {
      await _remote.createCourseworkItem(
        type: type.value,
        delivery: delivery.value,
        title: title,
        description: description,
        subject: subject,
        section: section,
        dueDate: dueDate,
        totalPoints: totalPoints,
        published: published,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
      );
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> updateCourseworkItem({
    required String itemId,
    required CourseworkType type,
    required CourseworkDelivery delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) {
    return _run(() => _remote.updateCourseworkItem(
          itemId: itemId,
          type: type.value,
        delivery: delivery.value,
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
  }

  @override
  Future<Result<void>> deleteCourseworkItem(String itemId) =>
      _run(() => _remote.softDeleteCourseworkItem(itemId));

  @override
  Stream<List<StudentSummary>> watchStudentsInSection(String section) =>
      _remote.watchStudentsInSection(section);

  @override
  Stream<List<Grade>> watchGradesFor({
    required String subject,
    required String section,
    String? term,
  }) =>
      _remote.watchGradesFor(subject: subject, section: section, term: term);

  @override
  Stream<List<ClassAssessment>> watchClassAssessments({
    required String subject,
    required String section,
    required String term,
  }) =>
      _remote.watchClassAssessments(subject: subject, section: section, term: term);

  @override
  Stream<SubjectWeights?> watchClassWeights({
    required String subject,
    required String section,
  }) =>
      _remote.watchClassWeights(subject: subject, section: section);

  @override
  Stream<String?> watchClassWeightsSetBy({
    required String subject,
    required String section,
  }) =>
      _remote.watchClassWeightsSetBy(subject: subject, section: section);

  @override
  Future<Result<({String assessmentId, List<String> marksOverMax})>>
      saveClassAssessment({
    String? assessmentId,
    required String subject,
    required String section,
    required String term,
    required String title,
    required GradingComponent component,
    required double maxScore,
  }) async {
    try {
      return Success(await _remote.saveClassAssessment(
        assessmentId: assessmentId,
        subject: subject,
        section: section,
        term: term,
        title: title,
        component: component,
        maxScore: maxScore,
      ));
    } on ServerException catch (e) {
      // The server's own words. It names the total that was refused and
      // the children whose marks no longer fit, and a screen that
      // flattened that to "something went wrong" would leave a teacher
      // with nothing to act on.
      return Error(ValidationFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<({int saved, int cleared})>> saveAssessmentScores({
    required String assessmentId,
    required List<ScoreEntry> scores,
  }) async {
    try {
      return Success(await _remote.saveAssessmentScores(
        assessmentId: assessmentId,
        scores: scores,
      ));
    } on ServerException catch (e) {
      return Error(ValidationFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> setClassWeights({
    required String subject,
    required String section,
    SubjectWeights? weights,
  }) async {
    try {
      await _remote.setClassWeights(
        subject: subject,
        section: section,
        weights: weights,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ValidationFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> submitGrade({
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
  }) async {
    try {
      await _remote.submitGrade(
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
      );
      return const Success(null);
    } on ServerException catch (e) {
      // The server names the child and the total it refused, and an
      // import reports one line per rejected row -- a generic failure
      // there tells a teacher forty rows went wrong and nothing else.
      return Error(ValidationFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<GradingScheme> watchGradingScheme() => _remote.watchGradingScheme();

  @override
  Future<Result<void>> saveGradingScheme(GradingScheme scheme) async {
    try {
      await _remote.saveGradingScheme(scheme);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> confirmGradingScheme() async {
    try {
      await _remote.confirmGradingScheme();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
