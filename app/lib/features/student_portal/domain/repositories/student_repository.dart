import '../../../faculty_portal/domain/entities/coursework_item.dart';
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
}
