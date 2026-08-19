enum AttendanceStatus {
  present('present'),
  late('late'),
  absent('absent'),
  excused('excused');

  final String value;
  const AttendanceStatus(this.value);

  static AttendanceStatus fromString(String value) =>
      AttendanceStatus.values.firstWhere((s) => s.value == value);

  String get displayLabel => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.excused => 'Excused',
      };
}

enum AttendanceSubjectType {
  student('student'),
  employee('employee');

  final String value;
  const AttendanceSubjectType(this.value);

  static AttendanceSubjectType fromString(String value) =>
      AttendanceSubjectType.values.firstWhere((s) => s.value == value);
}

class AttendanceRecord {
  final String id;
  final String personId;
  final String personRole;
  final AttendanceSubjectType subjectType;
  final String date; // 'YYYY-MM-DD'
  final DateTime timestampIn;
  final DateTime? timestampOut;
  final AttendanceStatus status;
  final String? location;

  const AttendanceRecord({
    required this.id,
    required this.personId,
    required this.personRole,
    required this.subjectType,
    required this.date,
    required this.timestampIn,
    required this.status,
    this.timestampOut,
    this.location,
  });

  bool get hasTimedOut => timestampOut != null;
}
