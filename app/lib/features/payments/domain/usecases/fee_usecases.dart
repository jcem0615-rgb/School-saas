import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/assessment.dart';
import '../entities/fee_structure.dart';
import '../entities/discount.dart';
import '../entities/installment.dart';
import '../entities/receipt_booklet.dart';
import '../entities/subsidy.dart';
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
      return ValidationFailure('"${line.label}" must be more than zero. '
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
      'The payment plan adds up to ${planned.toStringAsFixed(2)} but the '
      'fees come to ${total.toStringAsFixed(2)}. They have to match.',
    );
  }
  return null;
}

/// Checks the discounts before they are granted.
///
/// Returns the complaint, or null when they are sound. The server checks
/// the same things; this exists so a registrar finds out with the line
/// named, before the round trip.
ValidationFailure? checkDiscounts(List<Discount> discounts, double grossTotal) {
  if (discounts.isEmpty) return null;

  for (final discount in discounts) {
    if (discount.label.trim().isEmpty) {
      return const ValidationFailure('Every discount needs a name. A family '
          'reading the assessment has to know what was taken off and why.');
    }
    if (discount.amount <= 0) {
      return ValidationFailure('"${discount.label}" must take off more than '
          'zero. Remove the line instead.');
    }
    final rate = discount.percentage;
    if (rate != null && (rate <= 0 || rate > 100)) {
      return ValidationFailure('"${discount.label}" is ${rate}%. A discount '
          'is between 0 and 100 per cent.');
    }
  }

  // A school may waive the whole amount and not a centavo more. Past
  // that the charge goes negative and the school is paying a family to
  // enrol -- which the balance arithmetic would carry without complaint.
  final given = totalDiscount(discounts);
  if (given > grossTotal + 0.005) {
    return ValidationFailure(
      'The discounts come to ${given.toStringAsFixed(2)} against fees of '
      '${grossTotal.toStringAsFixed(2)}. A school can waive the whole amount, '
      'but it cannot charge less than nothing.',
    );
  }
  return null;
}

/// Checks the government subsidies before they are recorded.
///
/// [remainingAfterDiscounts] rather than the gross: a student on both a
/// sibling discount and an ESC grant must not have the two together come
/// to more than the fees, and checking the grant against the published
/// figure alone would let them.
ValidationFailure? checkSubsidies(List<Subsidy> subsidies, double remainingAfterDiscounts) {
  if (subsidies.isEmpty) return null;

  final seen = <String>{};
  for (final subsidy in subsidies) {
    final reference = subsidy.referenceNumber.trim();
    if (reference.isEmpty) {
      return ValidationFailure(
        'The ${subsidy.programme.displayLabel.toLowerCase()} needs the '
        'certificate or voucher number it will be claimed against. Without '
        'one the school cannot bill for it, and the family has simply been '
        'charged less.',
      );
    }
    // One certificate is claimed once. PEAC rejects the second -- after
    // the family has been charged as though both were coming.
    final key = '${subsidy.programme.value}|${reference.toLowerCase()}';
    if (!seen.add(key)) {
      return ValidationFailure('$reference appears twice on this assessment. '
          'One certificate is claimed once.');
    }
    if (subsidy.amount <= 0) {
      return ValidationFailure('The subsidy against $reference must be more '
          'than zero.');
    }
  }

  final granted = totalSubsidy(subsidies);
  if (granted > remainingAfterDiscounts + 0.005) {
    return ValidationFailure(
      'The subsidies come to ${granted.toStringAsFixed(2)} against '
      '${remainingAfterDiscounts.toStringAsFixed(2)} still chargeable after '
      'discounts. A grant can cover the whole of what is left and no more.',
    );
  }
  return null;
}

/// Registers or closes an official-receipt booklet.
///
/// The range is checked here as well as by the editor, because a booklet
/// whose last number is below its first would make the whole series
/// unreconcilable: every number in it would read as outside the range.
class SaveReceiptBookletUseCase {
  final PaymentRepository _repository;
  const SaveReceiptBookletUseCase(this._repository);

  Future<Result<void>> call({String? bookletId, required ReceiptBooklet booklet}) {
    if (booklet.firstNumber <= 0) {
      return Future.value(const Error(
          ValidationFailure('A booklet starts at a number above zero.')));
    }
    if (booklet.lastNumber < booklet.firstNumber) {
      return Future.value(Error(ValidationFailure(
        'The booklet ends at ${booklet.lastNumber} and starts at '
        '${booklet.firstNumber}. The last number has to be at least the first.',
      )));
    }
    // A booklet of a hundred thousand is a typo -- somebody pasted a
    // permit number into the range -- and reconciling it would build a
    // hundred thousand rows.
    if (booklet.capacity > 10000) {
      return Future.value(const Error(ValidationFailure(
        'That range covers more than ten thousand receipts. Check the first '
        'and last numbers against the booklet.',
      )));
    }
    return _repository.saveReceiptBooklet(bookletId: bookletId, booklet: booklet);
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
    List<Installment> installments = const [],
    List<Discount> discounts = const [],
    List<Subsidy> subsidies = const [],
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

    final gross = items.fold<double>(0, (sum, i) => sum + i.amount);
    final discountProblem = checkDiscounts(discounts, gross);
    if (discountProblem != null) return Future.value(Error(discountProblem));

    final afterDiscounts = gross - totalDiscount(discounts);
    final subsidyProblem = checkSubsidies(subsidies, afterDiscounts);
    if (subsidyProblem != null) return Future.value(Error(subsidyProblem));

    // Against the net, because that is what the family owes and what the
    // server will check. A discounted or subsidised family still gets a
    // payment plan, for their own share of it.
    final planProblem =
        checkInstallments(installments, afterDiscounts - totalSubsidy(subsidies));
    if (planProblem != null) return Future.value(Error(planProblem));

    return _repository.assessStudentFees(
      studentId: studentId.trim(),
      schoolYear: schoolYear.trim(),
      items: items,
      installments: installments,
      discounts: discounts,
      subsidies: subsidies,
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
