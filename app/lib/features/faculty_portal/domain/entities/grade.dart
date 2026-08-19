class Grade {
  final String id;
  final String studentId;
  final String studentName;
  final String subject;
  final String section;
  final String term;
  final String? courseworkItemId;
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
    this.courseworkItemId,
    this.remarks,
  });

  double get percentage => maxScore == 0 ? 0 : (score / maxScore) * 100;
}
