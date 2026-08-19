enum MeetingStatus {
  scheduled('scheduled'),
  cancelled('cancelled'),
  completed('completed');

  final String value;
  const MeetingStatus(this.value);

  static MeetingStatus fromString(String value) =>
      MeetingStatus.values.firstWhere((s) => s.value == value);
}

class Meeting {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final List<String> attendeeRoles;
  final MeetingStatus status;
  final String createdByName;

  const Meeting({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.attendeeRoles,
    required this.status,
    required this.createdByName,
    this.description,
    this.location,
  });

  bool get isUpcoming => status == MeetingStatus.scheduled && startTime.isAfter(DateTime.now());
}
