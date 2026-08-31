import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../faculty_portal/domain/entities/grading_scheme.dart';
import '../../../faculty_portal/domain/entities/quarterly_grade.dart';
import '../entities/promotion.dart';
import '../entities/student_summary.dart';
import '../repositories/registrar_repository.dart';

/// Draws up what the marks say should happen to one section.
///
/// Reads the section's marks, computes each student's quarterly grades
/// through the same function the report card prints from, and turns them
/// into a recommendation per student. Nothing is written; this produces
/// the list a registrar reads.
class BuildRolloverPlanUseCase {
  final RegistrarRepository _repository;
  const BuildRolloverPlanUseCase(this._repository);

  Future<Result<List<PromotionCandidate>>> call({
    required List<StudentSummary> section,
    required GradingScheme scheme,
    required Set<EducationLevel> divisionsInUse,
  }) async {
    if (section.isEmpty) {
      return const Error(ValidationFailure('There is nobody in that section.'));
    }
    try {
      final grades = await _repository.fetchGradesForSection(section.first.section);

      final byStudent = <String, List<Grade>>{};
      for (final grade in grades) {
        (byStudent[grade.studentId] ??= []).add(grade);
      }

      return Success([
        for (final student in section)
          recommendPromotion(
            student: student,
            yearsGrades: _quarterlyGrades(byStudent[student.id] ?? const [], scheme),
            divisionsInUse: divisionsInUse,
          ),
      ]);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  /// Every subject-and-quarter this student has marks in, computed.
  ///
  /// Through `computeQuarterlyGrade` rather than by averaging raw scores,
  /// so the number a promotion turns on is the same number on the report
  /// card. Two ways of computing a grade is how a school ends up with a
  /// child promoted on one screen and retained on another.
  static List<QuarterlyGrade> _quarterlyGrades(List<Grade> grades, GradingScheme scheme) {
    final groups = <String, List<Grade>>{};
    for (final grade in grades) {
      (groups['${grade.subject}|${grade.term}'] ??= []).add(grade);
    }
    return [
      for (final entry in groups.entries)
        computeQuarterlyGrade(
          subject: entry.value.first.subject,
          term: entry.value.first.term,
          grades: entry.value,
          scheme: scheme,
        ),
    ];
  }
}

/// Applies a page of decisions.
class RunRolloverUseCase {
  final RegistrarRepository _repository;
  const RunRolloverUseCase(this._repository);

  Future<Result<RolloverOutcome>> call({
    required String schoolYear,
    required List<PromotionDecision> decisions,
  }) {
    if (decisions.isEmpty) {
      return Future.value(const Error(ValidationFailure('There is nothing to roll over.')));
    }

    // "No decision" is left out of the run entirely rather than written
    // as a record.
    //
    // This is not tidiness. A promotion record is what marks a student
    // as done for the year, and it is what a re-run skips on -- so
    // writing one for a student nobody has decided about would lock them
    // out of the rollover permanently. A registrar who runs this before
    // the last marks are in must be able to come back for those students
    // once the marks arrive, and this is what makes that work.
    final actionable = decisions
        .where((d) => d.outcome != PromotionOutcome.held)
        .toList();
    if (actionable.isEmpty) {
      return Future.value(const Error(ValidationFailure(
        'Every student here is still marked "No decision". Nothing to apply '
        'yet -- decide them, or come back once their marks are in.',
      )));
    }

    // A promotion with nowhere to go would blank the student's year and
    // leave a child missing off every class list in September. The
    // server refuses it too; this catches it while the registrar is
    // still looking at the row that caused it.
    final homeless = actionable
        .where((d) => d.outcome == PromotionOutcome.promoted)
        .where((d) => d.toGradeLevel.trim().isEmpty || d.toSection.trim().isEmpty)
        .toList();
    if (homeless.isNotEmpty) {
      final names = homeless.take(3).map((d) => d.studentName).join(', ');
      return Future.value(Error(ValidationFailure(
        'These students are being promoted with no year and section to go '
        'to: $names${homeless.length > 3 ? ' and ${homeless.length - 3} more' : ''}.',
      )));
    }

    return _repository.runYearEndRollover(
      schoolYear: schoolYear,
      decisions: actionable,
    );
  }
}
