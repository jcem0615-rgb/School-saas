import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/timekeeping/domain/entities/leave_request.dart';
import 'package:logicclass/features/timekeeping/domain/entities/timesheet.dart';

/// The month a payroll clerk reads.
///
/// This is where "did not scan" becomes either absence or approved
/// leave, and that decision reaches a payslip. Everything here is the
/// pure function; nothing fetches.
void main() {
  AttendanceRecord scan(
    String date, {
    required int inHour,
    int? outHour,
    AttendanceStatus status = AttendanceStatus.present,
    String personId = 'emp_1',
  }) {
    final parts = date.split('-').map(int.parse).toList();
    return AttendanceRecord(
      id: '${date}_$personId',
      personId: personId,
      personRole: 'staff',
      subjectType: AttendanceSubjectType.employee,
      date: date,
      timestampIn: DateTime(parts[0], parts[1], parts[2], inHour),
      timestampOut:
          outHour == null ? null : DateTime(parts[0], parts[1], parts[2], outHour),
      status: status,
    );
  }

  LeaveRequest leave(
    String from,
    String to, {
    LeaveStatus status = LeaveStatus.approved,
    LeaveType type = LeaveType.sick,
    String employeeUid = 'emp_1',
  }) =>
      LeaveRequest(
        id: 'lv_$from',
        employeeUid: employeeUid,
        employeeName: 'Ana Cruz',
        employeeRole: 'staff',
        type: type,
        fromDate: from,
        toDate: to,
        days: 1,
        reason: 'Fever',
        status: status,
        createdAt: DateTime(2026, 3, 1),
      );

  Timesheet build({
    List<AttendanceRecord> records = const [],
    List<LeaveRequest> leaves = const [],
    DateTime? from,
    DateTime? to,
    Set<int> restDays = const {6, 7},
  }) =>
      buildTimesheet(
        employeeUid: 'emp_1',
        employeeName: 'Ana Cruz',
        // Monday 2 March to Sunday 8 March 2026: a whole week, so every
        // case below has both working days and a weekend in it.
        from: from ?? DateTime(2026, 3, 2),
        to: to ?? DateTime(2026, 3, 8),
        records: records,
        leaves: leaves,
        restDays: restDays,
      );

  group('a day with no scan', () {
    test('is absence on a working day', () {
      final sheet = build();
      expect(sheet.daysAbsent, 5); // Monday to Friday
      expect(sheet.daysWorked, 0);
    });

    test('is a rest day at the weekend, never absence', () {
      // The distinction that matters: five absences in a week is a
      // conversation, seven is an accusation about two days nobody was
      // expected in.
      final sheet = build();
      final weekend =
          sheet.days.where((d) => d.kind == WorkDayKind.restDay).toList();
      expect(weekend.length, 2);
      expect(weekend.map((d) => d.date), ['2026-03-07', '2026-03-08']);
    });

    test('is leave when an approved request covers it', () {
      final sheet = build(leaves: [leave('2026-03-03', '2026-03-04')]);
      expect(sheet.daysOnLeave, 2);
      expect(sheet.daysAbsent, 3);
    });

    test('is still absence when the request was only filed', () {
      // A pending request is a plan. Counting it as leave would let
      // anybody take the day by filing for it.
      final sheet = build(
        leaves: [leave('2026-03-03', '2026-03-04', status: LeaveStatus.pending)],
      );
      expect(sheet.daysOnLeave, 0);
      expect(sheet.daysAbsent, 5);
    });

    test('is still absence when the request was declined', () {
      final sheet = build(
        leaves: [leave('2026-03-03', '2026-03-04', status: LeaveStatus.declined)],
      );
      expect(sheet.daysAbsent, 5);
    });
  });

  group('a day with a scan', () {
    test('counts as worked, with the hours between the scans', () {
      final sheet = build(records: [scan('2026-03-02', inHour: 8, outHour: 17)]);
      expect(sheet.daysWorked, 1);
      expect(sheet.minutesWorked, 9 * 60);
      expect(sheet.hoursWorkedLabel, '9h 00m');
    });

    test('counts as late when the scan says so, and still as worked', () {
      final sheet = build(records: [
        scan('2026-03-02', inHour: 9, outHour: 17, status: AttendanceStatus.late),
      ]);
      expect(sheet.daysLate, 1);
      // Late is not absent. Somebody who arrived at nine was at work.
      expect(sheet.daysWorked, 1);
      expect(sheet.daysAbsent, 4);
    });

    test('beats an approved leave for the same day', () {
      // Somebody who came in on their leave day was at work, whatever
      // the paperwork says.
      final sheet = build(
        records: [scan('2026-03-03', inHour: 8, outHour: 17)],
        leaves: [leave('2026-03-03', '2026-03-03')],
      );
      final day = sheet.days.firstWhere((d) => d.date == '2026-03-03');
      expect(day.kind, WorkDayKind.worked);
      expect(sheet.daysOnLeave, 0);
    });

    test('contributes no hours when nobody scanned out', () {
      // Not zero-and-silent, and not "until now" either: the system does
      // not know how long they stayed, and inventing hours puts them on
      // a payslip.
      final sheet = build(records: [scan('2026-03-02', inHour: 8)]);
      expect(sheet.daysWorked, 1);
      expect(sheet.minutesWorked, 0);
      // Surfaced separately, so the clerk knows the total is incomplete.
      expect(sheet.daysMissingTimeOut, 1);
    });

    test('takes the earlier arrival when a day somehow has two records', () {
      final sheet = build(records: [
        scan('2026-03-02', inHour: 11, outHour: 17),
        scan('2026-03-02', inHour: 8, outHour: 17),
      ]);
      final day = sheet.days.firstWhere((d) => d.date == '2026-03-02');
      expect(day.timeIn!.hour, 8);
    });

    test('ignores another employee entirely', () {
      final sheet = build(records: [
        scan('2026-03-02', inHour: 8, outHour: 17, personId: 'emp_2'),
      ]);
      expect(sheet.daysWorked, 0);
      expect(sheet.daysAbsent, 5);
    });
  });

  group('the shape of the week', () {
    test('covers every day between the bounds, inclusive', () {
      final sheet = build();
      expect(sheet.days.length, 7);
      expect(sheet.days.first.date, '2026-03-02');
      expect(sheet.days.last.date, '2026-03-08');
    });

    test('honours a school that works Saturdays', () {
      // Reporting every Saturday as absence would make the sheet useless
      // for a school that runs Saturday classes.
      final sheet = build(restDays: const {7});
      expect(sheet.workingDays, 6);
      expect(sheet.days.where((d) => d.kind == WorkDayKind.restDay).length, 1);
    });

    test('a single day is a single row', () {
      final sheet = build(
        from: DateTime(2026, 3, 2),
        to: DateTime(2026, 3, 2),
      );
      expect(sheet.days.length, 1);
    });
  });

  group('workingDaysBetween', () {
    test('counts weekdays inclusively', () {
      expect(
        workingDaysBetween(DateTime(2026, 3, 2), DateTime(2026, 3, 6)),
        5,
      );
    });

    test('skips the weekend in the middle', () {
      // Monday to the following Monday is six working days, not eight.
      expect(
        workingDaysBetween(DateTime(2026, 3, 2), DateTime(2026, 3, 9)),
        6,
      );
    });

    test('is one for a single weekday', () {
      expect(
        workingDaysBetween(DateTime(2026, 3, 2), DateTime(2026, 3, 2)),
        1,
      );
    });

    test('is zero for a weekend-only range', () {
      expect(
        workingDaysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 8)),
        0,
      );
    });

    test('is zero when the range runs backwards', () {
      // A request whose end is before its start is a mistake to reject,
      // not a negative day count to carry into a payslip.
      expect(
        workingDaysBetween(DateTime(2026, 3, 6), DateTime(2026, 3, 2)),
        0,
      );
    });
  });

  group('covers', () {
    test('includes both ends of the range', () {
      final request = leave('2026-03-03', '2026-03-05');
      expect(request.covers('2026-03-03'), isTrue);
      expect(request.covers('2026-03-04'), isTrue);
      expect(request.covers('2026-03-05'), isTrue);
      expect(request.covers('2026-03-02'), isFalse);
      expect(request.covers('2026-03-06'), isFalse);
    });

    test('compares dates correctly across a month boundary', () {
      // The reason the keys are zero-padded: '2026-03-30' < '2026-04-02'
      // as strings only because both halves are padded.
      final request = leave('2026-03-30', '2026-04-02');
      expect(request.covers('2026-04-01'), isTrue);
      expect(request.covers('2026-04-03'), isFalse);
    });
  });
}
