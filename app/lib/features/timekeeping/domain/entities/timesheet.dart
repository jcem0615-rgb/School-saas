import '../../../qr_attendance/domain/entities/attendance_record.dart';
import 'leave_request.dart';

/// What one day of an employee's month came to.
enum WorkDayKind {
  /// Scanned in. Worked, however briefly.
  worked,

  /// Scanned in after the cutoff.
  late,

  /// Approved leave covering this day.
  onLeave,

  /// A working day with no scan and no leave. The row a payroll clerk
  /// stops on.
  absent,

  /// Saturday or Sunday. Not absence, and never counted as such.
  restDay,
}

class TimesheetDay {
  final String date; // 'YYYY-MM-DD'
  final WorkDayKind kind;
  final DateTime? timeIn;
  final DateTime? timeOut;

  /// The leave that covers this day, when one does. Carried so the row
  /// can say *which* leave rather than only that there was some.
  final LeaveRequest? leave;

  const TimesheetDay({
    required this.date,
    required this.kind,
    this.timeIn,
    this.timeOut,
    this.leave,
  });

  /// Minutes between the scans, or null when one of them is missing.
  ///
  /// A day with a time in and no time out is deliberately null rather
  /// than zero or "until now": somebody forgot to scan out, and the
  /// honest answer is that this system does not know how long they
  /// stayed. Guessing would put invented hours on a payslip.
  int? get minutes => (timeIn == null || timeOut == null)
      ? null
      : timeOut!.difference(timeIn!).inMinutes.clamp(0, 60 * 24);

  bool get isWorkingDay => kind != WorkDayKind.restDay;
}

/// One employee, one period.
class Timesheet {
  final String employeeUid;
  final String employeeName;

  /// Inclusive 'YYYY-MM-DD' bounds.
  final String fromDate;
  final String toDate;

  final List<TimesheetDay> days;

  const Timesheet({
    required this.employeeUid,
    required this.employeeName,
    required this.fromDate,
    required this.toDate,
    required this.days,
  });

  int get daysWorked => days
      .where((d) => d.kind == WorkDayKind.worked || d.kind == WorkDayKind.late)
      .length;

  int get daysLate => days.where((d) => d.kind == WorkDayKind.late).length;

  int get daysOnLeave => days.where((d) => d.kind == WorkDayKind.onLeave).length;

  int get daysAbsent => days.where((d) => d.kind == WorkDayKind.absent).length;

  int get workingDays => days.where((d) => d.isWorkingDay).length;

  /// Total minutes across days that have both scans.
  int get minutesWorked =>
      days.fold(0, (sum, day) => sum + (day.minutes ?? 0));

  /// Days somebody scanned in and never scanned out.
  ///
  /// Surfaced as its own figure rather than folded into the total,
  /// because it is the difference between "these are the hours" and
  /// "these are the hours plus however long four unrecorded days were".
  /// A payroll clerk needs to know which they are holding.
  int get daysMissingTimeOut => days
      .where((d) => d.timeIn != null && d.timeOut == null)
      .length;

  String get hoursWorkedLabel {
    final hours = minutesWorked ~/ 60;
    final minutes = minutesWorked % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}

/// Turns the raw records into the month a payroll clerk reads.
///
/// Pure, and separate from anything that fetches: this is the part that
/// decides whether a missing day is absence or approved leave, and that
/// decision reaches a payslip. It is a function with a test rather than
/// a loop inside a widget.
Timesheet buildTimesheet({
  required String employeeUid,
  required String employeeName,
  required DateTime from,
  required DateTime to,
  required Iterable<AttendanceRecord> records,
  required Iterable<LeaveRequest> leaves,
  /// Weekday numbers (1 = Monday) the school does not work. Configurable
  /// rather than hard-coded, because a school running Saturday classes
  /// should not have every Saturday reported as absence.
  Set<int> restDays = const {6, 7},
}) {
  final byDate = <String, AttendanceRecord>{};
  for (final record in records) {
    if (record.personId != employeeUid) continue;
    // One record per person per day is the invariant markAttendance
    // maintains through its derived id. Where two somehow exist, the
    // earlier time in is the one that counts -- that is when they
    // arrived.
    final existing = byDate[record.date];
    if (existing == null || record.timestampIn.isBefore(existing.timestampIn)) {
      byDate[record.date] = record;
    }
  }

  // Only approved leave counts. A pending request is a plan, and a
  // declined one is a day somebody was expected in.
  final approved = leaves
      .where((l) => l.employeeUid == employeeUid && l.status == LeaveStatus.approved)
      .toList();

  final days = <TimesheetDay>[];
  for (var day = _midnight(from);
      !day.isAfter(_midnight(to));
      day = day.add(const Duration(days: 1))) {
    final key = dateKeyOf(day);
    final record = byDate[key];
    final leave = approved.where((l) => l.covers(key)).firstOrNull;

    final WorkDayKind kind;
    if (record != null) {
      // A scan beats everything. Somebody who came in on their approved
      // leave day was at work, and the record says so.
      kind = record.status == AttendanceStatus.late
          ? WorkDayKind.late
          : WorkDayKind.worked;
    } else if (leave != null) {
      kind = WorkDayKind.onLeave;
    } else if (restDays.contains(day.weekday)) {
      kind = WorkDayKind.restDay;
    } else {
      kind = WorkDayKind.absent;
    }

    days.add(TimesheetDay(
      date: key,
      kind: kind,
      timeIn: record?.timestampIn,
      timeOut: record?.timestampOut,
      leave: leave,
    ));
  }

  return Timesheet(
    employeeUid: employeeUid,
    employeeName: employeeName,
    fromDate: dateKeyOf(from),
    toDate: dateKeyOf(to),
    days: days,
  );
}

/// Working days between two dates, inclusive, weekends excluded.
///
/// What a leave request is counted in. Returns zero rather than a
/// negative for a range that runs backwards -- a request whose end is
/// before its start is a mistake to reject, not a number to invent.
int workingDaysBetween(DateTime from, DateTime to, {Set<int> restDays = const {6, 7}}) {
  var day = _midnight(from);
  final last = _midnight(to);
  if (day.isAfter(last)) return 0;
  var count = 0;
  while (!day.isAfter(last)) {
    if (!restDays.contains(day.weekday)) count += 1;
    day = day.add(const Duration(days: 1));
  }
  return count;
}

/// 'YYYY-MM-DD', the same key the attendance records use.
String dateKeyOf(DateTime at) {
  final month = at.month.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  return '${at.year}-$month-$day';
}

/// Midnight local, so adding a day never lands on the same date twice
/// across a daylight-saving boundary somebody else's server observes.
DateTime _midnight(DateTime at) => DateTime(at.year, at.month, at.day);
