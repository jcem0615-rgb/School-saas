import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/assessment.dart';
import '../entities/fee_structure.dart';
import '../entities/installment.dart';
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
    List<Installment> installments = const [],
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

    final planProblem = checkInstallments(
      installments,
      items.fold<double>(0, (sum, i) => sum + i.amount),
    );
    if (planProblem != null) return Future.value(Error(planProblem));

    return _repository.saveFeeStructure(
      structureId: structureId,
      name: name.trim(),
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      schoolYear: schoolYear.trim(),
      items: items,
      installments: installments,
      isActive: isActive,
    );
  }
}

/// Checks a payment plan before it is saved or charged.
///
/// Returns the complaint, or null when the plan is sound. Shared by both
/// use cases below because a plan is wrong in the same ways whether it is
/// being published on a schedule or charged to a family, and two copies
/// of these rules would drift.
///
/// The server checks all of it again. This exists so a bursar finds out
/// with the line named, before the round trip.
ValidationFailure? checkInstallments(List<Installment> installments, double total) {
  if (installments.isEmpty) return null;

  for (final line in installments) {
    if (line.label.trim().isEmpty) {
      return const ValidationFailure('Every instalment needs a name -- '
          '"Upon enrolment", "October", whatever the letter home calls it.');
    }
    if (line.amount <= 0) {
      return ValidationFailure('"\${line.label}" must be more than zero. '
          'Remove the line instead.');
    }
  }

  final labels = installments.map((i) => i.label.trim().toLowerCase()).toList();
  if (labels.toSet().length != labels.length) {
    return const ValidationFailure('Two instalments have the same name. '
        'A family cannot tell which payment they are being asked for.');
  }

  // The one that matters. A plan that does not add up to the charge
  // either tells a family they have finished paying when they have not,
  // or chases them for money nobody charged them.
  final planned = installments.fold<double>(0, (sum, i) => sum + i.amount);
  if ((planned - total).abs() > 0.01) {
    return ValidationFailure(
      'The payment plan adds up to \${planned.toStringAsFixed(2)} but the '
      'fees come to \${total.toStringAsFixed(2)}. They have to match.',
    );
  }
  return null;
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
    List<Installment> installments = const [],
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

    final planProblem = checkInstallments(
      installments,
      items.fold<double>(0, (sum, i) => sum + i.amount),
    );
    if (planProblem != null) return Future.value(Error(planProblem));

    return _repository.assessStudentFees(
      studentId: studentId.trim(),
      schoolYear: schoolYear.trim(),
      items: items,
      installments: installments,
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
