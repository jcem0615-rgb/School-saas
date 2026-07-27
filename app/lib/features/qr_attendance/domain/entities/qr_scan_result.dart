import 'attendance_record.dart';

enum ScanAction {
  timeIn('time_in'),
  timeOut('time_out'),
  alreadyCompleted('already_completed');

  final String value;
  const ScanAction(this.value);

  static ScanAction fromString(String value) =>
      ScanAction.values.firstWhere((a) => a.value == value);
}

/// Result returned from the markAttendance Cloud Function -- what the
/// scanner sees immediately after a successful scan (name, action taken,
/// resulting status), distinct from [AttendanceRecord] which is the
/// persisted Firestore document read back later for history/reports.
class QrScanResult {
  final String personId;
  final String personName;
  final String personRole;
  final ScanAction action;
  final AttendanceStatus status;
  final DateTime timestamp;

  const QrScanResult({
    required this.personId,
    required this.personName,
    required this.personRole,
    required this.action,
    required this.status,
    required this.timestamp,
  });
}
