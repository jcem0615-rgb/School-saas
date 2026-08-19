import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/education_level.dart';
import '../../domain/entities/student_summary.dart';

class StudentSummaryModel extends StudentSummary {
  const StudentSummaryModel({
    required super.id,
    required super.studentNumber,
    required super.firstName,
    required super.lastName,
    required super.educationLevel,
    required super.gradeLevel,
    required super.section,
    required super.status,
    required super.balance,
    required super.enrollmentDate,
    super.middleName,
    super.programId,
    super.programName,
    super.department,
    super.userId,
    super.photoUrl,
    super.guardianContacts,
  });

  factory StudentSummaryModel.fromFirestore(String id, Map<String, dynamic> data) {
    final rawGuardians = data['guardianContacts'] as List<dynamic>? ?? [];
    return StudentSummaryModel(
      id: id,
      studentNumber: data['studentNumber'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      middleName: data['middleName'] as String?,
      // Defaults to elementary for any pre-existing record written before
      // this field was required, rather than throwing -- keeps old data
      // readable while every new registration requires it explicitly.
      educationLevel: EducationLevel.fromString(data['educationLevel'] as String? ?? 'elementary'),
      gradeLevel: data['gradeLevel'] as String? ?? '',
      section: data['section'] as String? ?? '',
      programId: data['programId'] as String?,
      programName: data['programName'] as String?,
      department: data['department'] as String?,
      status: StudentStatus.fromString(data['status'] as String? ?? 'enrolled'),
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      userId: data['userId'] as String?,
      photoUrl: data['photoUrl'] as String?,
      enrollmentDate: (data['enrollmentDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      guardianContacts: rawGuardians.map((raw) {
        final g = raw as Map<String, dynamic>;
        return GuardianContact(
          name: g['name'] as String? ?? '',
          relationship: g['relationship'] as String? ?? '',
          phone: g['phone'] as String? ?? '',
          email: g['email'] as String?,
        );
      }).toList(),
    );
  }
}
