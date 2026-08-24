import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';

/// The Director's headline number is not allowed to read 0%.
///
/// It did, for a day: the seed skipped weekends, so a demo opened on a
/// Saturday showed a school where nobody had turned up. "Today" is whatever
/// day the demo is actually run, so this cannot be pinned to a fixture date
/// -- the test asserts the property that matters on every day of the week.
void main() {
  test('today has attendance whatever day the demo is opened', () {
    final store = DemoStore();
    addTearDown(store.dispose);

    final today = store.attendance.value.where((a) => a.date == store.todayKey);
    expect(today, isNotEmpty,
        reason: 'a demo opened on a weekend still has to show a school day');
  });

  test('the rate counts students, and is a plausible school day', () async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'director@demo.ph'),
        );

    final store = container.read(demoStoreProvider);
    final enrolled = store.students.value
        .where((s) => s.status == StudentStatus.enrolled)
        .length;
    final scannedToday = store.attendance.value
        .where((a) =>
            a.date == store.todayKey &&
            a.subjectType == AttendanceSubjectType.student)
        .length;

    expect(enrolled, greaterThan(1));
    // Most of the school is in, but not all of it -- one student is out
    // each day, so the number moves and reads as real.
    expect(scannedToday, enrolled - 1,
        reason: 'one absence a day, and no faculty scan counted as a student');

    final rate = scannedToday / enrolled;
    expect(rate, greaterThan(0.5));
    expect(rate, lessThan(1.0),
        reason: 'a permanent 100% would look as fake as a permanent 0%');
  });

  test('the student the demo signs in as is not the one marked absent', () {
    final store = DemoStore();
    addTearDown(store.dispose);

    // Rotating one absence a day is what makes the rate move, but starting
    // that rotation on the demo's own student meant "My Attendance" opened
    // on a list missing today -- the same empty screen, one portal over.
    final me = store.students.value.firstWhere((s) => s.userId == 'u_student');
    final mine = store.attendance.value
        .where((a) => a.personId == me.id && a.date == store.todayKey);

    expect(mine, hasLength(1));
  });

  test("today's collections are not zero either", () {
    final store = DemoStore();
    addTearDown(store.dispose);

    final today = store.payments.value.where((p) =>
        !p.isRefund &&
        p.createdAt.year == store.now.year &&
        p.createdAt.month == store.now.month &&
        p.createdAt.day == store.now.day);

    expect(today, isNotEmpty);
    expect(today.fold<double>(0, (sum, p) => sum + p.amount), greaterThan(0));
    for (final p in today) {
      expect(p.createdAt.isAfter(store.now), isFalse,
          reason: 'a receipt issued later today has not happened yet');
    }
  });
}
