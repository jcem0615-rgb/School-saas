import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/class_sessions/domain/entities/class_session.dart';

/// The arithmetic behind "when did this student arrive", which is the
/// part of the register a parent and a payroll both end up reading.
void main() {
  final bell = DateTime(2026, 3, 3, 7, 30);
  final halfway = DateTime(2026, 3, 3, 8, 0);

  group('timeInForMark', () {
    test('puts a present student on the bell', () {
      expect(timeInForMark(AttendanceStatus.present, bell, halfway), bell);
    });

    test('puts a late student at the moment they were marked', () {
      // The defect this replaced kept whatever was already on the row,
      // and every row on a fresh register carries the bell time -- so a
      // student marked late was recorded as having been on time.
      expect(timeInForMark(AttendanceStatus.late, bell, halfway), halfway);
    });

    test('gives an absent student no arrival at all', () {
      expect(timeInForMark(AttendanceStatus.absent, bell, halfway), isNull);
    });

    test('gives an excused student none either', () {
      expect(timeInForMark(AttendanceStatus.excused, bell, halfway), isNull);
    });

    test('will not let a slow clock put an arrival before the class began', () {
      final early = DateTime(2026, 3, 3, 7, 20);
      expect(timeInForMark(AttendanceStatus.late, bell, early), bell);
    });
  });
}
