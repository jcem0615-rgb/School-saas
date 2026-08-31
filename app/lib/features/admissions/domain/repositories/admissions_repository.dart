import '../../../../core/errors/result.dart';
import '../../../../core/constants/education_level.dart';
import '../entities/applicant.dart';

/// What was created, so the screen can tell the family their reference
/// while they are still on the phone.
class SavedApplicant {
  final String applicantId;
  final String? referenceNumber;
  const SavedApplicant({required this.applicantId, this.referenceNumber});
}

/// What enrolling produced.
class EnrolledApplicant {
  final String studentId;
  final String studentNumber;

  /// The reservation fee carried onto the student record as a credit.
  final double openingCredit;

  const EnrolledApplicant({
    required this.studentId,
    required this.studentNumber,
    required this.openingCredit,
  });
}

abstract class AdmissionsRepository {
  /// Every enquiry on file, newest first.
  Stream<List<Applicant>> watchApplicants();

  Future<Result<SavedApplicant>> saveApplicant({
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
  });

  /// Moves a family one step, with whatever that step produced.
  Future<Result<void>> advanceApplicant({
    required String applicantId,
    required AdmissionStage stage,
    DateTime? examScheduledFor,
    double? examScore,
    double? examMaxScore,
    double? reservationFee,
    String? reservationReference,
    String? notes,
  });

  /// Creates the student record. Refused if it has already been done.
  Future<Result<EnrolledApplicant>> enrolApplicant({
    required String applicantId,
    required String section,
    required DateTime birthDate,
  });
}
