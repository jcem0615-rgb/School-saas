import 'grading_scheme.dart';

/// One piece of work a class was given: one column in the class record.
///
/// This is what the grading module was missing, and its absence was the
/// worst thing about it. A mark used to be posted and never replaced --
/// `submitGrade` wrote a new document every time -- and the quarterly
/// arithmetic sums the scores and the maximums inside a component, so a
/// teacher who typed 80 out of 10 and corrected it to 8 out of 10 left
/// the child on 88 out of 20. Nothing on any screen said so. The import
/// knew, and worked around it by refusing a row identical to one already
/// on file, which catches a file run twice and does nothing whatever
/// about a correction -- a corrected mark is by definition not identical.
///
/// Giving the work an identity fixes it by construction: one student's
/// mark against one assessment is one document, at a derived id, so
/// entering it again replaces it.
class ClassAssessment {
  final String id;
  final String subject;
  final String section;

  /// The quarter this belongs to: Q1, Q2, Q3, Q4.
  final String term;

  /// What the teacher calls it. "Quiz 1", "Long test", "Group report".
  final String title;

  final GradingComponent component;

  /// What it is marked out of. The denominator of the component
  /// percentage, and what every mark against it is checked against.
  final double maxScore;

  final String createdByName;
  final DateTime createdAt;

  const ClassAssessment({
    required this.id,
    required this.subject,
    required this.section,
    required this.term,
    required this.title,
    required this.component,
    required this.maxScore,
    required this.createdByName,
    required this.createdAt,
  });

  /// "Quiz 1 · WW · out of 20", for a column header.
  String get columnLabel => '$title · ${component.shortLabel} · /${_trim(maxScore)}';
}

/// One student's mark against one assessment, as the class record holds
/// it while the teacher is typing.
///
/// Null means blank, and blank is not zero. A child who did not sit the
/// quiz has the piece of work left out of both their score and the total
/// it is over; a child who scored nothing has the total counted against
/// them. Collapsing the two marks an absent child as having failed.
class ScoreEntry {
  final String studentId;
  final String studentName;
  final double? score;

  const ScoreEntry({
    required this.studentId,
    required this.studentName,
    this.score,
  });

  ScoreEntry withScore(double? value) =>
      ScoreEntry(studentId: studentId, studentName: studentName, score: value);
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// A document id that is stable for the same class, and safe as a path.
///
/// Must match `classKey` in `functions/src/shared/grading/assessment.ts`
/// exactly: this is what the class-weights document is keyed by, and the
/// two disagreeing means a teacher sets a split the screen never reads
/// back. Subjects and sections are free text a school types -- "Grade 10
/// - Rizal", "Mathematics 7" -- so they are lower-cased and reduced to a
/// narrow alphabet, which also makes "Mathematics" and "mathematics "
/// one class rather than two.
String classKeyFor(String subject, String section) {
  String part(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = slug.length > 60 ? slug.substring(0, 60) : slug;
    return trimmed.isEmpty ? 'none' : trimmed;
  }

  return '${part(subject)}__${part(section)}';
}
