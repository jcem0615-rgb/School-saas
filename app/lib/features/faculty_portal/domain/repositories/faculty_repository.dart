import '../../../../core/errors/result.dart';
import '../entities/coursework_item.dart';
import '../entities/grade.dart';

abstract class FacultyRepository {
  /// Scoped to the signed-in teacher's own items -- a Faculty member sees
  /// their own coursework list, not every teacher's, on this screen.
  /// (A school-wide or student-facing view is a different query, built in
  /// the Student Portal module.)
  Stream<List<CourseworkItem>> watchMyCourseworkItems();

  Future<Result<void>> createCourseworkItem({
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
  });

  Stream<List<Grade>> watchGradesFor({required String subject, required String section});

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
