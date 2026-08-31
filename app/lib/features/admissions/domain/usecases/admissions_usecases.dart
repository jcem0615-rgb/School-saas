import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/applicant.dart';
import '../repositories/admissions_repository.dart';

class WatchApplicantsUseCase {
  final AdmissionsRepository _repository;
  const WatchApplicantsUseCase(this._repository);

  Stream<List<Applicant>> call() => _repository.watchApplicants();
}

/// Takes down an enquiry, or corrects one.
///
/// The checks are deliberately few. An enquiry is typed while the caller
/// is still on the line, and a form that refuses to save without a middle
/// name is a form that gets abandoned -- and then the enquiry is a note
/// on paper again, which is the thing this module exists to stop.
class SaveApplicantUseCase {
  final AdmissionsRepository _repository;
  const SaveApplicantUseCase(this._repository);

  Future<Result<SavedApplicant>> call({
    String? applicantId,
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    String? programId,
    required String guardianName,
    required String guardianPhone,
    String? guardianEmail,
    String? source,
    String? notes,
  }) {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('The applicant\'s name is required.')),
      );
    }
    if (guardianName.trim().isEmpty || guardianPhone.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure(
        'A parent or guardian and a number to ring them on are required. An '
        'applicant nobody can contact is not a lead.',
      )));
    }
    if (gradeLevel.trim().isEmpty) {
      return Future.value(const Error(
        ValidationFailure('Which year they are applying into is required.'),
      ));
    }
    if (educationLevel.usesProgramCatalogue &&
        (programId == null || programId.trim().isEmpty)) {
      return Future.value(Error(ValidationFailure(
        'A ${educationLevel.shortLabel} applicant needs a '
        '${educationLevel.programLabel.toLowerCase()}.',
      )));
    }

    return _repository.saveApplicant(
      applicantId: applicantId,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      middleName: middleName?.trim(),
      educationLevel: educationLevel,
      gradeLevel: gradeLevel.trim(),
      programId: programId?.trim(),
      guardianName: guardianName.trim(),
      guardianPhone: guardianPhone.trim(),
      guardianEmail: guardianEmail?.trim(),
      source: source?.trim(),
      notes: notes?.trim(),
    );
  }
}

/// Moves a family one step, with the evidence that step produced.
///
/// The step and its evidence are one act. A family is not at "exam
/// taken" without a score and not at "reserved" without a payment, and
/// letting the stage be set first and the number filled in later leaves
/// half the pipeline as stages with nothing behind them -- which is the
/// logbook this module replaces.
class AdvanceApplicantUseCase {
  final AdmissionsRepository _repository;
  const AdvanceApplicantUseCase(this._repository);

  Future<Result<void>> call({
    required Applicant applicant,
    required AdmissionStage stage,
    DateTime? examScheduledFor,
    double? examScore,
    double? examMaxScore,
    double? reservationFee,
    String? reservationReference,
    String? notes,
  }) {
    if (!nextStagesFrom(applicant.stage).contains(stage)) {
      return Future.value(Error(ValidationFailure(
        '${applicant.fullName} is at "${applicant.stage.displayLabel}" and '
        'cannot be moved straight to "${stage.displayLabel}".',
      )));
    }

    if (stage == AdmissionStage.examScheduled && examScheduledFor == null) {
      return Future.value(const Error(ValidationFailure(
        'Booking a family in for the entrance exam needs a date. Without one, '
        '"exam scheduled" says nothing anybody can act on.',
      )));
    }

    if (stage == AdmissionStage.examTaken) {
      if (examScore == null || examMaxScore == null) {
        return Future.value(const Error(ValidationFailure(
          'Record the score and what the paper was out of.',
        )));
      }
      if (examMaxScore <= 0) {
        return Future.value(const Error(ValidationFailure(
          'What the entrance exam was out of has to be more than zero.',
        )));
      }
      if (examScore < 0 || examScore > examMaxScore) {
        // Almost always the two fields the wrong way round, and it would
        // rank a child above everybody who sat the same paper.
        return Future.value(Error(ValidationFailure(
          'A score of $examScore is not a mark out of $examMaxScore. Check the '
          'two fields are the right way round.',
        )));
      }
    }

    if (stage == AdmissionStage.reserved &&
        (reservationFee == null || reservationFee <= 0)) {
      return Future.value(const Error(ValidationFailure(
        'A place is reserved by a payment. Record what the family paid.',
      )));
    }

    return _repository.advanceApplicant(
      applicantId: applicant.id,
      stage: stage,
      examScheduledFor: examScheduledFor,
      examScore: examScore,
      examMaxScore: examMaxScore,
      reservationFee: reservationFee,
      reservationReference: reservationReference,
      notes: notes,
    );
  }
}

/// Creates the student record behind an applicant.
class EnrolApplicantUseCase {
  final AdmissionsRepository _repository;
  const EnrolApplicantUseCase(this._repository);

  Future<Result<EnrolledApplicant>> call({
    required Applicant applicant,
    required String section,
    required DateTime birthDate,
  }) {
    if (applicant.hasEnrolled) {
      return Future.value(Error(ValidationFailure(
        '${applicant.fullName} has already been enrolled. Their student record '
        'is on the roster.',
      )));
    }
    if (applicant.stage != AdmissionStage.reserved &&
        applicant.stage != AdmissionStage.offered) {
      return Future.value(const Error(ValidationFailure(
        'Only a family who has been offered a place can be enrolled.',
      )));
    }
    if (section.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure(
        'Which class they are joining is required. A student with no section '
        'is on no class list.',
      )));
    }
    if (birthDate.isAfter(DateTime.now())) {
      return Future.value(
        const Error(ValidationFailure('A birthday cannot be in the future.')),
      );
    }

    return _repository.enrolApplicant(
      applicantId: applicant.id,
      section: section.trim(),
      birthDate: birthDate,
    );
  }
}
