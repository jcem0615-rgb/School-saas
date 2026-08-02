import '../../../../core/constants/education_level.dart';

/// One entry in the school's curriculum catalogue: a Senior High strand
/// ("STEM", under the Academic track) or a College degree program ("BS
/// Computer Science", under the College of Computer Studies).
///
/// Both are the same shape -- a name, a short code, and the grouping the
/// school reports it under -- and both answer the same question at
/// registration: "what is this student enrolled in?". One collection
/// rather than two keeps `students.programId` a single foreign key and
/// keeps the division-scoping rules in firestore.rules unchanged.
///
/// Elementary and Junior High have no entry here at all. Their grade
/// level and section say everything the record needs, which is why the
/// registration form shows them no catalogue field.
class Program {
  final String id;
  final String name;
  final String code;

  /// The grouping this is reported under: a DepEd track for a Senior High
  /// strand ("Academic", "TVL"), a college department for a degree
  /// program. Denormalized onto the student record at registration, which
  /// is what lets firestore.rules department-scope access with a single
  /// lookup rather than a join.
  final String department;

  /// Which division this belongs to. Only [EducationLevel.seniorHigh] and
  /// [EducationLevel.college] ever appear.
  final EducationLevel educationLevel;

  const Program({
    required this.id,
    required this.name,
    required this.code,
    required this.department,
    this.educationLevel = EducationLevel.college,
  });

  /// DepEd calls a Senior High grouping a track; a college calls it a
  /// department. Same field, different word to the user.
  String get departmentLabel =>
      educationLevel == EducationLevel.seniorHigh ? 'Track' : 'Department';
}
