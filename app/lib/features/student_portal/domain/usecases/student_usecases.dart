import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/coursework_submission.dart';
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

/// Hands work in against one piece of coursework.
class SubmitCourseworkUseCase {
  final StudentRepository _repository;
  const SubmitCourseworkUseCase(this._repository);

  Future<Result<void>> call({
    String? submissionId,
    required CourseworkItem item,
    required String studentId,
    required String studentName,
    required String section,
    required String answer,
    String? attachmentUrl,
    String? attachmentName,
  }) {
    // Lesson plans and lessons are material to read, not work to hand
    // in. Accepting a submission against one would put a row in the
    // teacher's list for something they never asked anyone to do.
    if (!item.acceptsSubmissions) {
      return Future.value(Error(ValidationFailure(
        'A ${item.type.displayLabel.toLowerCase()} is material to read, not work to submit.',
      )));
    }

    // Something has to have been handed in. A submission with an empty
    // answer and no file is somebody tapping Submit by accident, and
    // recording it as done is worse than not recording it -- the student
    // believes they are finished and the teacher sees a blank.
    final hasAnswer = answer.trim().isNotEmpty;
    final hasFile = attachmentUrl != null && attachmentUrl.isNotEmpty;
    if (!hasAnswer && !hasFile) {
      return Future.value(const Error(ValidationFailure(
        'Write an answer or attach a file before submitting.',
      )));
    }

    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing student record.')));
    }

    return _repository.submitCoursework(
      submissionId: submissionId,
      item: item,
      studentId: studentId,
      studentName: studentName,
      section: section,
      answer: answer.trim(),
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
    );
  }
}

class WatchMySubmissionsUseCase {
  final StudentRepository _repository;
  const WatchMySubmissionsUseCase(this._repository);

  Stream<List<CourseworkSubmission>> call(String studentId) =>
      _repository.watchMySubmissions(studentId);
}
