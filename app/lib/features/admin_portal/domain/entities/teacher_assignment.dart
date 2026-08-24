/// A teacher's responsibility for one subject in one section.
class TeacherAssignment {
  final String id;
  final String teacherId;
  final String teacherName;
  final String subject;
  final String section;
  final String schoolYear;

  /// Whether this teacher is the section's *adviser* -- the one person
  /// responsible for the class as a whole, not just for a subject in it.
  ///
  /// A flag on the ordinary assignment rather than a separate collection,
  /// because an adviser is almost always already teaching that section
  /// and a parallel record would be a second place for the same fact to
  /// be wrong. It carries real weight: the adviser is who a student's
  /// emergency alert wakes up.
  final bool isAdviser;

  const TeacherAssignment({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    required this.subject,
    required this.section,
    required this.schoolYear,
    this.isAdviser = false,
  });
}
