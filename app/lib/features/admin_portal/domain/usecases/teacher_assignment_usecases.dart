import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
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

class UpdateTeacherAssignmentUseCase {
  final AdminRepository _repository;
  const UpdateTeacherAssignmentUseCase(this._repository);

  Future<Result<void>> call({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) {
    if (assignmentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing assignment.')));
    }
    if (teacherId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Select a teacher.')));
    }
    final subjectError = Validators.required(subject, fieldName: 'Subject');
    if (subjectError != null) return Future.value(Error(ValidationFailure(subjectError)));

    final sectionError = Validators.required(section, fieldName: 'Section');
    if (sectionError != null) return Future.value(Error(ValidationFailure(sectionError)));

    return _repository.updateTeacherAssignment(
      assignmentId: assignmentId,
      teacherId: teacherId,
      teacherName: teacherName,
      subject: subject.trim(),
      section: section.trim(),
      schoolYear: schoolYear.trim(),
    );
  }
}

class DeleteTeacherAssignmentUseCase {
  final AdminRepository _repository;
  const DeleteTeacherAssignmentUseCase(this._repository);

  Future<Result<void>> call(String assignmentId) {
    if (assignmentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing assignment.')));
    }
    return _repository.deleteTeacherAssignment(assignmentId);
  }
}
