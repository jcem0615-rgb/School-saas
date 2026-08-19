enum SummonsStatus {
  pending('pending'),
  completed('completed'),
  cancelled('cancelled');

  final String value;
  const SummonsStatus(this.value);

  static SummonsStatus fromString(String value) =>
      SummonsStatus.values.firstWhere((s) => s.value == value);

  String get displayLabel => switch (this) {
        SummonsStatus.pending => 'Pending',
        SummonsStatus.completed => 'Completed',
        SummonsStatus.cancelled => 'Cancelled',
      };
}

/// A request for a student (and by extension their family) to report to
/// the guidance office. Unlike [GuidanceRecord], a summons IS visible to
/// the student and their linked parent -- being called in is exactly the
/// kind of thing a family needs to know about, even though the
/// underlying counseling notes stay private.
class Summons {
  final String id;
  final String studentId;
  final String studentName;
  final String reason;
  final DateTime scheduledDate;
  final SummonsStatus status;
  final String issuedByName;
  final DateTime createdAt;

  const Summons({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.reason,
    required this.scheduledDate,
    required this.status,
    required this.issuedByName,
    required this.createdAt,
  });
}
