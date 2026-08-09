import '../../../../core/errors/result.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/coursework_submission.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';

/// Deliberately reuses entities already defined by Registrar Portal
/// (StudentSummary), Faculty Portal (CourseworkItem, Grade), and Admin
/// Portal (TeacherAssignment) rather than duplicating parallel "student-
/// facing" versions of the same shapes -- a student's assignment is the
/// exact same [CourseworkItem] their teacher created, just queried and
/// filtered differently. Promissory Notes reuse Director Portal's
/// generic approvals system directly from the presentation layer (same
/// pattern as Faculty Portal's Material Requests), so there's no
/// corresponding method here.
abstract class StudentRepository {
  /// Resolves the signed-in student's own academic record by querying
  /// students where userId == the current uid. Every other method on
  /// this repository needs the resulting studentId/section, so screens
  /// typically call this first.
  Stream<StudentSummary?> watchMyStudentRecord();

  Stream<List<TeacherAssignment>> watchMySubjects(String section);

  Stream<List<CourseworkItem>> watchMyCoursework(String section, {CourseworkType? typeFilter});

  Stream<List<Grade>> watchMyGrades(String studentId);

  /// Everything this student has handed in, across all their coursework.
  /// One stream rather than a per-item query so the coursework feed can
  /// mark what is already done without N reads.
  Stream<List<CourseworkSubmission>> watchMySubmissions(String studentId);

  /// Hands work in, or replaces what was handed in before.
  ///
  /// [submissionId] is null for a first submission and the existing id
  /// when revising -- one method rather than two because the student is
  /// doing the same thing either way, and splitting it invites a screen
  /// to create a duplicate instead of replacing.
  Future<Result<void>> submitCoursework({
    String? submissionId,
    required CourseworkItem item,
    required String studentId,
    required String studentName,
    required String section,
    required String answer,
    List<String> answers = const [],
    String? attachmentUrl,
    String? attachmentName,
  });
}
