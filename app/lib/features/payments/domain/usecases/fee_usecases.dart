import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/assessment.dart';
import '../entities/fee_structure.dart';
import '../repositories/payment_repository.dart';

/// The school's published fee schedules.
class WatchFeeStructuresUseCase {
  final PaymentRepository _repository;
  const WatchFeeStructuresUseCase(this._repository);

  Stream<List<FeeStructure>> call() => _repository.watchFeeStructures();
}

/// Publishes or edits a fee schedule.
///
/// The checks here are about a schedule being usable rather than merely
/// storable. One with no items charges nothing; one with a zero-cost line
/// is a line somebody forgot to fill in, and it would print on every
/// family's assessment as "Laboratory Fee — 0.00", which reads as an
/// error in the school's paperwork rather than as a free lab.
class SaveFeeStructureUseCase {
  final PaymentRepository _repository;
  const SaveFeeStructureUseCase(this._repository);

  Future<Result<void>> call({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    bool isActive = true,
  }) {
    if (name.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Give the schedule a name.')));
    }
    if (schoolYear.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('A schedule belongs to a school year.')),
      );
    }
    if (items.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Add at least one fee to the schedule.')),
      );
    }
    for (final item in items) {
      if (item.label.trim().isEmpty) {
        return Future.value(const Error(ValidationFailure('Every fee needs a name.')));
      }
      if (item.amount <= 0) {
        return Future.value(
          Error(ValidationFailure('"${item.label}" must cost more than zero. '
              'Remove the line instead.')),
        );
      }
    }
    // Two lines with the same name on one schedule is a duplicate paste,
    // and on the printed assessment it is indistinguishable from being
    // charged twice for the same thing.
    final labels = items.map((i) => i.label.trim().toLowerCase()).toList();
    if (labels.toSet().length != labels.length) {
      return Future.value(
        const Error(ValidationFailure('Two fees on this schedule have the same name.')),
      );
    }

    return _repository.saveFeeStructure(
      structureId: structureId,
      name: name.trim(),
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      schoolYear: schoolYear.trim(),
      items: items,
      isActive: isActive,
    );
  }
}

/// What one student has been charged.
class WatchAssessmentsUseCase {
  final PaymentRepository _repository;
  const WatchAssessmentsUseCase(this._repository);

  Stream<List<Assessment>> call(String studentId) => _repository.watchAssessments(studentId);
}

/// Charges fees to a student.
///
/// The server checks all of this again -- it has to, since a callable is
/// reachable without going through this screen -- but failing here means
/// a registrar finds out before the round trip, with the field named.
class AssessStudentFeesUseCase {
  final PaymentRepository _repository;
  const AssessStudentFeesUseCase(this._repository);

  Future<Result<AssessmentOutcome>> call({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A student must be selected.')));
    }
    if (schoolYear.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('An assessment belongs to a school year.')),
      );
    }
    if (items.isEmpty) {
      return Future.value(const Error(ValidationFailure('There is nothing to charge.')));
    }
    for (final item in items) {
      if (item.label.trim().isEmpty) {
        return Future.value(const Error(ValidationFailure('Every fee needs a name.')));
      }
      if (item.amount <= 0) {
        return Future.value(
          Error(ValidationFailure('"${item.label}" must cost more than zero.')),
        );
      }
    }

    return _repository.assessStudentFees(
      studentId: studentId.trim(),
      schoolYear: schoolYear.trim(),
      items: items,
      sourceStructureId: sourceStructureId,
      sourceStructureName: sourceStructureName,
      remarks: remarks?.trim().isEmpty ?? true ? null : remarks!.trim(),
    );
  }
}

/// Reverses an assessment.
///
/// A reason is required for the same reason the release log requires a
/// purpose: a reversal with nothing said about it is the entry an
/// auditor stops at.
class VoidAssessmentUseCase {
  final PaymentRepository _repository;
  const VoidAssessmentUseCase(this._repository);

  Future<Result<void>> call({required String assessmentId, required String reason}) {
    if (assessmentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing assessment.')));
    }
    if (reason.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Say why this assessment is being voided.')),
      );
    }
    return _repository.voidAssessment(assessmentId: assessmentId, reason: reason.trim());
  }
}
