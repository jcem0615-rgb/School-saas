import 'attendance_record.dart';

/// What a scan did. Every value markAttendance.ts can return.
///
/// [tooSoon] was missing, and its absence was not a wrong label -- it was
/// a crash. `fromString` had no fallback, so the server's `too_soon`
/// threw "Bad state: No element" inside the scanner, on the single most
/// common event at a gate: the same ID going past twice while the queue
/// backs up. The server has a long comment explaining how carefully it
/// handles that; the client could not receive the answer.
enum ScanAction {
  timeIn('time_in'),
  timeOut('time_out'),

  /// Scanned again too soon after timing in. Nothing was written, and
  /// nothing should have been: signing somebody out seconds after they
  /// arrived is a day's pay for an hourly employee.
  tooSoon('too_soon'),

  alreadyCompleted('already_completed');

  final String value;
  const ScanAction(this.value);

  /// Names the value it did not recognise.
  ///
  /// A deployed scanner meeting an action from a newer server should say
  /// what it saw rather than "No element", which is a sentence nobody at
  /// a gate can act on and nobody reading a crash report can either.
  static ScanAction fromString(String value) => ScanAction.values.firstWhere(
        (a) => a.value == value,
        orElse: () => throw ArgumentError.value(
          value,
          'action',
          'Not a scan outcome this app knows. The scanner may be older '
              'than the server it is talking to.',
        ),
      );
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

  /// How long somebody has to have been in before a second scan means
  /// they are leaving.
  ///
  /// The server sends it so the scanner can say how long to wait rather
  /// than just refusing. It was sent and never read: the one number that
  /// turns "that did not work" into "they are already in, try again in
  /// five minutes" was on the wire the whole time.
  final int minimumDwellMinutes;

  const QrScanResult({
    required this.personId,
    required this.personName,
    required this.personRole,
    required this.action,
    required this.status,
    required this.timestamp,
    this.minimumDwellMinutes = 5,
  });
}
