import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/grade.dart';
import '../repositories/faculty_repository.dart';

class WatchGradesUseCase {
  final FacultyRepository _repository;
  const WatchGradesUseCase(this._repository);

  Stream<List<Grade>> call({required String subject, required String section}) =>
      _repository.watchGradesFor(subject: subject, section: section);
}

class SubmitGradeUseCase {
  final FacultyRepository _repository;
  const SubmitGradeUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    String? courseworkItemId,
    String? remarks,
  }) {
    if (maxScore <= 0) {
      return Future.value(const Error(ValidationFailure('Max score must be greater than zero.')));
    }
    if (score < 0) {
      return Future.value(const Error(ValidationFailure('Score cannot be negative.')));
    }
    if (score > maxScore) {
      return Future.value(const Error(ValidationFailure('Score cannot exceed max score.')));
    }
    return _repository.submitGrade(
      studentId: studentId,
      studentName: studentName,
      subject: subject,
      section: section,
      term: term,
      score: score,
      maxScore: maxScore,
      courseworkItemId: courseworkItemId,
      remarks: remarks?.trim(),
    );
  }
}
