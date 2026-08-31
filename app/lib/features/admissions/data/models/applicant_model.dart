import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/education_level.dart';
import '../../domain/entities/applicant.dart';

class ApplicantModel extends Applicant {
  const ApplicantModel({
    required super.id,
    required super.referenceNumber,
    required super.firstName,
    required super.lastName,
    required super.educationLevel,
    required super.gradeLevel,
    required super.guardianName,
    required super.guardianPhone,
    required super.stage,
    required super.inquiredAt,
    required super.stageChangedAt,
    super.middleName,
    super.programId,
    super.programName,
    super.guardianEmail,
    super.source,
    super.examScheduledFor,
    super.examScore,
    super.examMaxScore,
    super.reservationFeePaid,
    super.reservationPaidAt,
    super.reservationReference,
    super.studentId,
    super.notes,
    super.lastUpdatedByName,
  });

  factory ApplicantModel.fromFirestore(String id, Map<String, dynamic> data) {
    // Written by a callable with serverTimestamp, so both dates are
    // briefly null on the local echo of a fresh write. Falling back to
    // now keeps a new enquiry off the follow-up list for its first
    // moments rather than putting it at the top of it.
    final inquired = (data['inquiredAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return ApplicantModel(
      id: id,
      referenceNumber: data['referenceNumber'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      middleName: data['middleName'] as String?,
      educationLevel:
          EducationLevel.tryFromString(data['educationLevel'] as String? ?? '') ??
              EducationLevel.elementary,
      gradeLevel: data['gradeLevel'] as String? ?? '',
      programId: data['programId'] as String?,
      programName: data['programName'] as String?,
      guardianName: data['guardianName'] as String? ?? '',
      guardianPhone: data['guardianPhone'] as String? ?? '',
      guardianEmail: data['guardianEmail'] as String?,
      source: data['source'] as String?,
      stage: AdmissionStage.fromString(data['stage'] as String? ?? ''),
      inquiredAt: inquired,
      stageChangedAt: (data['stageChangedAt'] as Timestamp?)?.toDate() ?? inquired,
      examScheduledFor: (data['examScheduledFor'] as Timestamp?)?.toDate(),
      examScore: (data['examScore'] as num?)?.toDouble(),
      examMaxScore: (data['examMaxScore'] as num?)?.toDouble(),
      reservationFeePaid: (data['reservationFeePaid'] as num?)?.toDouble() ?? 0,
      reservationPaidAt: (data['reservationPaidAt'] as Timestamp?)?.toDate(),
      reservationReference: data['reservationReference'] as String?,
      studentId: data['studentId'] as String?,
      notes: data['notes'] as String?,
      lastUpdatedByName: data['lastUpdatedByName'] as String?,
    );
  }
}
