class DailyReport {
  final String id;
  final String date; // 'YYYY-MM-DD'
  final String content;
  final String staffName;
  final DateTime submittedAt;

  const DailyReport({
    required this.id,
    required this.date,
    required this.content,
    required this.staffName,
    required this.submittedAt,
  });
}
