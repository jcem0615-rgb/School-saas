import '../../../../core/constants/education_level.dart';

enum StudentStatus {
  enrolled('enrolled'),
  inactive('inactive'),
  graduated('graduated'),
  transferredOut('transferred_out');

  final String value;
  const StudentStatus(this.value);

  static StudentStatus fromString(String value) =>
      StudentStatus.values.firstWhere((s) => s.value == value);

  String get displayLabel => switch (this) {
        StudentStatus.enrolled => 'Enrolled',
        StudentStatus.inactive => 'Inactive',
        StudentStatus.graduated => 'Graduated',
        StudentStatus.transferredOut => 'Transferred Out',
      };
}

class GuardianContact {
  final String name;
  final String relationship;
  final String phone;
  final String? email;
  const GuardianContact({required this.name, required this.relationship, required this.phone, this.email});
}

/// A student's academic record -- exists independently of a portal
/// account (see docs/10-registrar-portal.md). [userId] is null until the
/// Registrar provisions a Student Portal login for this record.
///
/// [educationLevel] is required for every student (Elementary/High
/// School/College). [department] is denormalized from the student's
/// [programName]/[programId] at registration time when college -- this is
/// what lets firestore.rules division/department-scope access with a
/// single lookup, never an extra join (see docs/15-divisions-and-programs.md).
class StudentSummary {
  final String id;
  final String studentNumber;
  final String firstName;
  final String lastName;
  final String? middleName;
  final EducationLevel educationLevel;
  final String gradeLevel;
  final String section;
  final String? programId;
  final String? programName;
  final String? department;
  final StudentStatus status;
  final double balance;
  final String? userId;
  final String? photoUrl;
  final DateTime enrollmentDate;
  final List<GuardianContact> guardianContacts;

  const StudentSummary({
    required this.id,
    required this.studentNumber,
    required this.firstName,
    required this.lastName,
    required this.educationLevel,
    required this.gradeLevel,
    required this.section,
    required this.status,
    required this.balance,
    required this.enrollmentDate,
    this.middleName,
    this.programId,
    this.programName,
    this.department,
    this.userId,
    this.photoUrl,
    this.guardianContacts = const [],
  });

  String get fullName => '$firstName $lastName';
  bool get hasPortalAccount => userId != null;
  bool get isCollege => educationLevel == EducationLevel.college;
}
