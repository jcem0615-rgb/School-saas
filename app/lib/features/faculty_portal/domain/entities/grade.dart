import 'grading_scheme.dart';

class Grade {
  final String id;
  final String studentId;
  final String studentName;
  final String subject;
  final String section;
  final String term;
  final String? courseworkItemId;

  /// The piece of work this is a mark against.
  ///
  /// Null on marks written before assessments existed. Those still count
  /// towards their component exactly as they did -- they are simply not
  /// a column anybody can type into, which is what "posted and never
  /// replaceable" meant for them.
  final String? assessmentId;

  /// Which of the three DepEd components this score belongs to.
  ///
  /// Required for a quarterly grade to be computable at all, and
  /// defaulted rather than nullable so every score written before this
  /// existed still counts towards something. Written work is the least
  /// distorting default: it is where a quiz or a seatwork actually
  /// belongs, and it carries the smallest weight in only one of the three
  /// groupings.
  final GradingComponent component;
  final double score;
  final double maxScore;
  final String? remarks;
  final String submittedByName;
  final DateTime submittedAt;

  const Grade({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.subject,
    required this.section,
    required this.term,
    required this.score,
    required this.maxScore,
    required this.submittedByName,
    required this.submittedAt,
    this.component = GradingComponent.writtenWork,
    this.courseworkItemId,
    this.assessmentId,
    this.remarks,
  });

  double get percentage => maxScore == 0 ? 0 : (score / maxScore) * 100;
}
