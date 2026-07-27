import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../repositories/student_repository.dart';

class WatchMyStudentRecordUseCase {
  final StudentRepository _repository;
  const WatchMyStudentRecordUseCase(this._repository);

  Stream<StudentSummary?> call() => _repository.watchMyStudentRecord();
}

class WatchMySubjectsUseCase {
  final StudentRepository _repository;
  const WatchMySubjectsUseCase(this._repository);

  Stream<List<TeacherAssignment>> call(String section) => _repository.watchMySubjects(section);
}

class WatchMyCourseworkUseCase {
  final StudentRepository _repository;
  const WatchMyCourseworkUseCase(this._repository);

  Stream<List<CourseworkItem>> call(String section, {CourseworkType? typeFilter}) =>
      _repository.watchMyCoursework(section, typeFilter: typeFilter);
}

class WatchMyGradesUseCase {
  final StudentRepository _repository;
  const WatchMyGradesUseCase(this._repository);

  Stream<List<Grade>> call(String studentId) => _repository.watchMyGrades(studentId);
}
