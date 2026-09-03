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

  /// Printed on the student's ID card. Optional: a record with no birth
  /// date on file is still a valid enrolment.
  final DateTime? birthDate;

  /// The student's own address, and what their portal account is created
  /// against. Null for the many students who have none -- a Grade 1 pupil
  /// has no email, and a school that could not enrol that child until
  /// somebody invented one would end up with an invented one on file.
  final String? email;

  /// The student's own mobile number, as the office wrote it down.
  ///
  /// Two jobs. It is how the school reaches this student directly rather
  /// than through a guardian, and it is what a password reset by phone
  /// matches against -- so a student with none on file has no way back
  /// into their account except the counter.
  ///
  /// Stored as typed rather than normalised: `+63 917 555 0100` is what
  /// somebody reads out loud, and `639175550100` is not. The server
  /// checks it is a shape the matcher can read before storing it.
  final String? phone;

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
    this.birthDate,
    this.email,
    this.phone,
    this.guardianContacts = const [],
  });

  String get fullName => '$firstName $lastName';

  /// Where this student sits, said once.
  ///
  /// Sections in PH schools are almost always named after the grade they
  /// belong to -- "Grade 10 - Rizal", "BSCS 3-A" -- so printing
  /// "grade level - section" produced "Grade 10 - Grade 10 - Rizal" on
  /// every screen that showed both. On a phone that repetition is not
  /// just untidy: it is half a line of a two-line subtitle spent saying
  /// the same thing twice, and it pushed the useful part off the edge.
  ///
  /// Lives on the entity rather than in each screen so the four places
  /// that show it cannot disagree about what a class is called.
  String get classLabel {
    final grade = gradeLevel.trim();
    final sec = section.trim();
    if (grade.isEmpty) return sec;
    if (sec.isEmpty) return grade;
    // The common case: the section name already carries the grade.
    if (sec.toLowerCase().contains(grade.toLowerCase())) return sec;
    return '$grade - $sec';
  }

  bool get hasPortalAccount => userId != null;
  bool get isCollege => educationLevel == EducationLevel.college;

  /// Whether a portal account could be created for this student without
  /// the registrar having to go and find an address first.
  bool get canProvisionAccount => email?.trim().isNotEmpty ?? false;

  /// Somewhere to reach this family, in the order the school would try.
  ///
  /// The student's own number first, then the first guardian's. A student
  /// with neither is one the school cannot contact in an emergency, and
  /// that is worth being able to ask about.
  String? get reachablePhone {
    final own = phone?.trim();
    if (own != null && own.isNotEmpty) return own;
    for (final g in guardianContacts) {
      final p = g.phone.trim();
      if (p.isNotEmpty) return p;
    }
    return null;
  }

  /// An address to write to, the student's own before a guardian's.
  String? get reachableEmail {
    final own = email?.trim();
    if (own != null && own.isNotEmpty) return own;
    for (final g in guardianContacts) {
      final e = g.email?.trim();
      if (e != null && e.isNotEmpty) return e;
    }
    return null;
  }
}
