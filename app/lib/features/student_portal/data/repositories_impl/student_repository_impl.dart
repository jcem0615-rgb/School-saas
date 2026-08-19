import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/repositories/student_repository.dart';
import '../datasources/student_remote_datasource.dart';

class StudentRepositoryImpl implements StudentRepository {
  final StudentRemoteDataSource _remote;
  const StudentRepositoryImpl(this._remote);

  @override
  Stream<StudentSummary?> watchMyStudentRecord() => _remote.watchMyStudentRecord();

  @override
  Stream<List<TeacherAssignment>> watchMySubjects(String section) => _remote.watchMySubjects(section);

  @override
  Stream<List<CourseworkItem>> watchMyCoursework(String section, {CourseworkType? typeFilter}) =>
      _remote.watchMyCoursework(section, typeFilter: typeFilter);

  @override
  Stream<List<Grade>> watchMyGrades(String studentId) => _remote.watchMyGrades(studentId);
}
