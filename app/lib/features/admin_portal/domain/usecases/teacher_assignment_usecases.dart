import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/teacher_assignment.dart';
import '../repositories/admin_repository.dart';

class WatchTeacherAssignmentsUseCase {
  final AdminRepository _repository;
  const WatchTeacherAssignmentsUseCase(this._repository);

  Stream<List<TeacherAssignment>> call() => _repository.watchTeacherAssignments();
}

class CreateTeacherAssignmentUseCase {
  final AdminRepository _repository;
  const CreateTeacherAssignmentUseCase(this._repository);

  Future<Result<void>> call({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) {
    if (teacherId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A teacher must be selected.')));
    }
    if (subject.trim().isEmpty || section.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Subject and section are required.')));
    }
    return _repository.createTeacherAssignment(
      teacherId: teacherId.trim(),
      teacherName: teacherName.trim(),
      subject: subject.trim(),
      section: section.trim(),
      schoolYear: schoolYear.trim(),
    );
  }
}
