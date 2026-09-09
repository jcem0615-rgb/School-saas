import '../../../../core/errors/result.dart';
import '../entities/coursework_item.dart';
import '../entities/answer_key.dart';
import '../entities/coursework_submission.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/class_assessment.dart';
import '../entities/grade.dart';
import '../entities/grading_scheme.dart';

abstract class FacultyRepository {
  /// Scoped to the signed-in teacher's own items -- a Faculty member sees
  /// their own coursework list, not every teacher's, on this screen.
  /// (A school-wide or student-facing view is a different query, built in
  /// the Student Portal module.)
  Stream<List<CourseworkItem>> watchMyCourseworkItems();

  /// What has been handed in for one piece of coursework.
  Stream<List<CourseworkSubmission>> watchSubmissionsFor(String courseworkId);

  /// The correct answers, for the teacher who owns them. Students have no
  /// path to this at all -- there is no student-side equivalent, by
  /// design.
  Stream<AnswerKey?> watchAnswerKey(String courseworkId);

  Future<Result<void>> saveAnswerKey({
    required String courseworkId,
    required List<String> answers,
    required double pointsPerQuestion,
  });

  /// A teacher's own mark on one submission, overriding whatever the
  /// automatic pass produced.
  Future<Result<void>> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  });

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
  });

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
  });

  /// Soft delete: flips `isDeleted` rather than removing the document,
  /// since firestore.rules denies hard delete on every collection.
  Future<Result<void>> deleteCourseworkItem(String itemId);

  /// One class's marks, scoped to a quarter.
  ///
  /// [term] is not optional in spirit: without it this returns every mark
  /// the class was ever given, and anything that computes a quarterly
  /// grade from them adds quarters together. It stays nullable only for
  /// the one caller that genuinely wants the lot -- the student's own
  /// subject page, which groups by term itself.
  Stream<List<Grade>> watchGradesFor({
    required String subject,
    required String section,
    String? term,
  });

  /// The pieces of work one class was given in one quarter: the columns
  /// of the class record.
  Stream<List<ClassAssessment>> watchClassAssessments({
    required String subject,
    required String section,
    required String term,
  });

  /// The split this class is graded on, when the teacher has set one.
  /// Null means the school's confirmed scheme decides.
  Stream<SubjectWeights?> watchClassWeights({
    required String subject,
    required String section,
  });

  Stream<String?> watchClassWeightsSetBy({
    required String subject,
    required String section,
  });

  /// Creates or edits a piece of work. Names any marks that no longer
  /// fit its total rather than clamping them: either number could be the
  /// right one, and only the teacher knows which.
  Future<Result<({String assessmentId, List<String> marksOverMax})>>
      saveClassAssessment({
    String? assessmentId,
    required String subject,
    required String section,
    required String term,
    required String title,
    required GradingComponent component,
    required double maxScore,
  });

  /// Removes a piece of work and the marks recorded against it.
  ///
  /// The two go together: a column removed on its own would leave its
  /// marks still summing into the component total, so the class would
  /// keep being graded on a quiz that is no longer on any screen.
  /// Returns how many marks went with it, so the teacher is told.
  Future<Result<int>> deleteClassAssessment(String assessmentId);

  /// A whole column of marks at once, each replacing whatever was there.
  Future<Result<({int saved, int cleared})>> saveAssessmentScores({
    required String assessmentId,
    required List<ScoreEntry> scores,
  });

  /// Sets, or clears, what each component counts for this class.
  Future<Result<void>> setClassWeights({
    required String subject,
    required String section,
    SubjectWeights? weights,
  });

  /// The students enrolled in one section, so a teacher grades from a
  /// roster instead of typing student IDs from memory.
  Stream<List<StudentSummary>> watchStudentsInSection(String section);

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
  });

  /// The school's weights and transmutation table.
  ///
  /// Lives on the faculty repository because grading is what it is for,
  /// but it is read far beyond the staffroom: the student's own subject
  /// page and the report card both need it to say how a number was
  /// arrived at. The document is under settings/, readable by everyone in
  /// the tenant.
  Stream<GradingScheme> watchGradingScheme();

  /// Replaces the weights and the table. Revokes the confirmation --
  /// see the data source for why that is not the caller's choice.
  Future<Result<void>> saveGradingScheme(GradingScheme scheme);

  /// Records that somebody at the school has checked the weights.
  Future<Result<void>> confirmGradingScheme();
}
