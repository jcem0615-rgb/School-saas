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

  /// Null instead of throwing, for values that arrive from outside the
  /// app -- a stored document written by an older or newer build. A
  /// division nobody recognises is dropped from the set; it is not worth
  /// failing to render a school over.
  static EducationLevel? tryFromString(String value) {
    for (final l in EducationLevel.values) {
      if (l.value == value) return l;
    }
    return null;
  }

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

/// The short form used when a level is one end of a range. "Elementary to
/// Senior High School" reads correctly; "Elementary to Senior High School
/// School" does not, and neither does "Junior High School to College" once
/// it is a range rather than a division on its own.
extension EducationLevelRangeLabel on EducationLevel {
  String get shortLabel => switch (this) {
        EducationLevel.elementary => 'Elementary',
        EducationLevel.highSchool => 'Junior High',
        EducationLevel.seniorHigh => 'Senior High',
        EducationLevel.college => 'College',
      };
}

/// How wide a school is: which of the four divisions it actually runs.
///
/// Stored as the set rather than as one of a fixed list of combinations
/// ("elementary to senior high", "high school only", ...) because the
/// fixed list is never finished. A school that runs Elementary and
/// College but no high school at all exists, and a combination enum has
/// no row for it. A set has every combination there is, and this is what
/// turns it back into the phrase a person would say.
///
/// Contiguous runs read as a range; anything with a gap is listed out.
String educationCoverageLabel(Set<EducationLevel> levels) {
  if (levels.isEmpty) return 'Not specified';

  final ordered = EducationLevel.values.where(levels.contains).toList();
  if (ordered.length == 1) return ordered.first.displayLabel;

  final first = ordered.first.index;
  final last = ordered.last.index;
  final contiguous = last - first + 1 == ordered.length;
  if (contiguous) {
    return '${ordered.first.shortLabel} to ${ordered.last.displayLabel}';
  }

  final names = ordered.map((l) => l.displayLabel).toList();
  final lastName = names.removeLast();
  return '${names.join(', ')} and $lastName';
}

/// Reads a stored `educationLevels` array back into a set.
///
/// Tolerant on purpose: a missing field (every school created before this
/// was recorded) is an empty set, and an unrecognised entry is skipped
/// rather than thrown on.
Set<EducationLevel> parseEducationLevels(Object? raw) {
  if (raw is! List) return const <EducationLevel>{};
  return {
    for (final entry in raw)
      if (entry is String && EducationLevel.tryFromString(entry) != null)
        EducationLevel.fromString(entry),
  };
}
