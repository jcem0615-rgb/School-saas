import '../../../../core/errors/result.dart';
import '../entities/coursework_item.dart';
import '../entities/answer_key.dart';
import '../entities/coursework_submission.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/grade.dart';

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

  Stream<List<Grade>> watchGradesFor({required String subject, required String section});

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
    String? courseworkItemId,
    String? remarks,
  });
}
