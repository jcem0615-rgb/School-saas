/// The divisions every school in this system is organized around. A
/// single tenant (school) can run all four under one roof -- very common
/// for PH private schools -- and every student record declares which one
/// they belong to. This is what the division-isolation rules in
/// firestore.rules key off of (see docs/15-divisions-and-programs.md).
///
/// Senior High School is its own division rather than the tail end of
/// High School because that is what K-12 made it: Grades 11-12 pick a
/// track and strand, are taught by their own faculty, and are reported
/// to DepEd separately. Folding them into High School would mean a
/// Junior High teacher's division scope silently covered Senior High.
enum EducationLevel {
  elementary('elementary'),
  highSchool('high_school'),
  seniorHigh('senior_high'),
  college('college');

  final String value;
  const EducationLevel(this.value);

  static EducationLevel fromString(String value) =>
      EducationLevel.values.firstWhere((l) => l.value == value);

  String get displayLabel => switch (this) {
        EducationLevel.elementary => 'Elementary',
        EducationLevel.highSchool => 'Junior High School',
        EducationLevel.seniorHigh => 'Senior High School',
        EducationLevel.college => 'College',
      };

  /// Whether a student in this division enrols in something from the
  /// [Program] catalogue: a strand for Senior High, a degree program for
  /// College. Elementary and Junior High have neither -- their grade
  /// level and section say everything the record needs, which is why the
  /// registration form shows no catalogue field for them at all.
  bool get usesProgramCatalogue =>
      this == EducationLevel.seniorHigh || this == EducationLevel.college;

  /// What the catalogue is called to a user in this division. DepEd calls
  /// it a strand; a college calls it a program.
  String get programLabel =>
      this == EducationLevel.seniorHigh ? 'Strand' : 'Program / Course';
}
