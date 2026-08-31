import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/grade.dart';
import '../entities/grading_scheme.dart';
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
    required GradingComponent component,
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
      component: component,
      courseworkItemId: courseworkItemId,
      remarks: remarks?.trim(),
    );
  }
}

class WatchGradingSchemeUseCase {
  final FacultyRepository _repository;
  const WatchGradingSchemeUseCase(this._repository);

  Stream<GradingScheme> call() => _repository.watchGradingScheme();
}

class SaveGradingSchemeUseCase {
  final FacultyRepository _repository;
  const SaveGradingSchemeUseCase(this._repository);

  /// Refuses a scheme whose groups do not add up to a hundred.
  ///
  /// The one misconfiguration that does not announce itself: weights of
  /// 30/50/30 produce grades that look entirely plausible and are wrong
  /// for every child for a whole school year. Caught here rather than at
  /// the screen so an import or a script cannot get round it.
  Future<Result<void>> call(GradingScheme scheme) {
    if (scheme.weights.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('A grading scheme needs at least one group of subjects.')),
      );
    }
    final broken = scheme.unbalanced;
    if (broken.isNotEmpty) {
      final names = broken.map((w) => w.label).join(', ');
      return Future.value(Error(ValidationFailure(
        'Written work, performance tasks and quarterly assessment must add '
        'up to 100 per cent. These do not: $names.',
      )));
    }
    if (scheme.weights.where((w) => w.isFallback).length > 1) {
      return Future.value(const Error(ValidationFailure(
        'Only one group can be the catch-all for subjects that are not '
        'listed anywhere. Name the subjects in the others.',
      )));
    }
    return _repository.saveGradingScheme(scheme);
  }
}

class ConfirmGradingSchemeUseCase {
  final FacultyRepository _repository;
  const ConfirmGradingSchemeUseCase(this._repository);

  Future<Result<void>> call(GradingScheme scheme) {
    if (scheme.unbalanced.isNotEmpty) {
      return Future.value(const Error(ValidationFailure(
        'Fix the groups that do not add up to 100 before confirming.',
      )));
    }
    return _repository.confirmGradingScheme();
  }
}
