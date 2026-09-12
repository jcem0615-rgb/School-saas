import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/qr_scan_result.dart';
import 'package:logicclass/features/qr_attendance/presentation/controllers/qr_attendance_controller.dart';

/// What the scanner does with each of the four things a scan can mean.
///
/// `too_soon` was the one the app had no value for. `ScanAction.fromString`
/// used `firstWhere` with no fallback, so the server's answer threw "Bad
/// state: No element" inside the scanner -- on the most common event at a
/// gate, the same ID going past twice while the queue backs up. The
/// server has a long comment explaining how carefully it handles that;
/// the client could not receive the answer, and the demo never produced
/// one, so nothing caught it.
void main() {
  ProviderContainer scannerSignedIn() {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
        );
    return container;
  }

  String studentToken(ProviderContainer c) {
    final student = c.read(demoStoreProvider).students.value.first;
    return 'QR-STU-${student.studentNumber}';
  }

  group('every outcome the server can send', () {
    test('parses, including the one that used to throw', () {
      // Four values, and the enum has to carry all four: a missing one
      // is not a wrong label here, it is a crash.
      expect(ScanAction.fromString('time_in'), ScanAction.timeIn);
      expect(ScanAction.fromString('time_out'), ScanAction.timeOut);
      expect(ScanAction.fromString('too_soon'), ScanAction.tooSoon);
      expect(ScanAction.fromString('already_completed'), ScanAction.alreadyCompleted);
    });

    test('and an unknown one says what it saw', () {
      // "No element" is a sentence nobody at a gate can act on and
      // nobody reading a crash report can either.
      expect(
        () => ScanAction.fromString('teleported'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          contains('teleported'),
        )),
      );
    });
  });

  /// The four states a person can be in when their ID goes past, each
  /// set up rather than assumed: the demo seeds a record for today
  /// already, so a test that scanned twice and hoped would be testing the
  /// seed as much as the rule.
  group('what a scan means for the state the record is in', () {
    AttendanceRecord recordFor(String personId, {DateTime? inAt, DateTime? outAt}) =>
        AttendanceRecord(
          id: 'att_test',
          personId: personId,
          personRole: 'student',
          subjectType: AttendanceSubjectType.student,
          date: DateTime.now().toIso8601String().substring(0, 10),
          timestampIn: inAt ?? DateTime.now(),
          timestampOut: outAt,
          status: AttendanceStatus.present,
        );

    /// Replaces today's records with exactly [record], or none.
    void startFrom(ProviderContainer c, AttendanceRecord? record) {
      final store = c.read(demoStoreProvider);
      final others =
          store.attendance.value.where((a) => a.date != store.todayKey).toList();
      store.attendance.add([if (record != null) record, ...others]);
    }

    test('nothing yet today is a time in', () async {
      final container = scannerSignedIn();
      startFrom(container, null);
      final result = await container
          .read(qrAttendanceRepositoryProvider)
          .scanQrCode(qrToken: studentToken(container));
      expect(result.valueOrNull?.action, ScanAction.timeIn);
    });

    test('in a moment ago is refused, not treated as leaving', () async {
      // Without the floor the record says a person arrived and left in
      // the same minute -- for an hourly employee, a day's pay, and
      // nothing downstream flags it because both stamps are filled in.
      final container = scannerSignedIn();
      final student = container.read(demoStoreProvider).students.value.first;
      startFrom(container, recordFor(student.id, inAt: DateTime.now()));

      final result = await container
          .read(qrAttendanceRepositoryProvider)
          .scanQrCode(qrToken: studentToken(container));

      expect(result.valueOrNull?.action, ScanAction.tooSoon);
      // The number the message needs, sent by the server and previously
      // read by nobody.
      expect(result.valueOrNull?.minimumDwellMinutes, 5);
      // And nothing was written.
      final after = container.read(demoStoreProvider).attendance.value
          .firstWhere((a) => a.id == 'att_test');
      expect(after.timestampOut, isNull);
    });

    test('in since this morning is a time out', () async {
      final container = scannerSignedIn();
      final student = container.read(demoStoreProvider).students.value.first;
      startFrom(
        container,
        recordFor(student.id,
            inAt: DateTime.now().subtract(const Duration(hours: 6))),
      );

      final result = await container
          .read(qrAttendanceRepositoryProvider)
          .scanQrCode(qrToken: studentToken(container));

      expect(result.valueOrNull?.action, ScanAction.timeOut);
    });

    test('already out is neither, and writes nothing', () async {
      final container = scannerSignedIn();
      final student = container.read(demoStoreProvider).students.value.first;
      final out = DateTime.now().subtract(const Duration(hours: 1));
      startFrom(
        container,
        recordFor(student.id,
            inAt: DateTime.now().subtract(const Duration(hours: 8)), outAt: out),
      );

      final result = await container
          .read(qrAttendanceRepositoryProvider)
          .scanQrCode(qrToken: studentToken(container));

      expect(result.valueOrNull?.action, ScanAction.alreadyCompleted);
      final after = container.read(demoStoreProvider).attendance.value
          .firstWhere((a) => a.id == 'att_test');
      expect(after.timestampOut, out, reason: 'the first time out stands');
    });
  });

  test('an unknown token is refused rather than marking somebody', () async {
    final container = scannerSignedIn();
    final result = await container
        .read(qrAttendanceRepositoryProvider)
        .scanQrCode(qrToken: 'QR-STU-not-a-real-number');
    expect(result.isError, isTrue);
  });
}
