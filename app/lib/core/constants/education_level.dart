/// The three-way split every school in this system is organized around.
/// A single tenant (school) can run Elementary, High School, and College
/// under one roof -- very common for PH private schools -- and every
/// student record declares which one they belong to. This is what the
/// division-isolation rules in firestore.rules key off of (see
/// docs/15-divisions-and-programs.md).
enum EducationLevel {
  elementary('elementary'),
  highSchool('high_school'),
  college('college');

  final String value;
  const EducationLevel(this.value);

  static EducationLevel fromString(String value) =>
      EducationLevel.values.firstWhere((l) => l.value == value);

  String get displayLabel => switch (this) {
        EducationLevel.elementary => 'Elementary',
        EducationLevel.highSchool => 'High School',
        EducationLevel.college => 'College',
      };
}
