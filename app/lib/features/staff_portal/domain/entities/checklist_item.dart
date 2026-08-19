class ChecklistItem {
  final String id;
  final String task;
  final String date; // 'YYYY-MM-DD'
  final bool completed;
  final DateTime? completedAt;
  final String? notes;

  const ChecklistItem({
    required this.id,
    required this.task,
    required this.date,
    required this.completed,
    this.completedAt,
    this.notes,
  });
}
