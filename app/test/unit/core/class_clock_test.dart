import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/class_clock.dart';

/// How long the lesson has been running, and nothing about when it ends.
///
/// The countdown was removed on purpose: a lesson is not over because an
/// hour passed, and a screen telling a teacher in front of thirty
/// children that their time is up is making a decision that is not its
/// to make.
void main() {
  final opened = DateTime(2026, 9, 28, 8);

  ClassClock at(Duration into) =>
      ClassClock(openedAt: opened, now: opened.add(into));

  group('the class clock', () {
    test('counts up from the register opening', () {
      expect(at(const Duration(minutes: 8, seconds: 12)).elapsedLabel, '08:12');
    });

    test('never runs backwards on a device behind the server', () {
      // A phone a few seconds slow would otherwise show a lesson that
      // has not started yet.
      final behind = ClassClock(
        openedAt: opened,
        now: opened.subtract(const Duration(seconds: 30)),
      );
      expect(behind.elapsed, Duration.zero);
      expect(behind.elapsedLabel, '00:00');
    });

    test('shows hours only once there are some', () {
      // Eight minutes padded to 0:08:12 is noise; ninety minutes shown
      // as 90:00 leaves somebody doing arithmetic.
      expect(at(const Duration(minutes: 45)).elapsedLabel, '45:00');
      expect(at(const Duration(hours: 1, minutes: 30)).elapsedLabel, '1:30:00');
    });

    test('keeps going past an hour without complaint', () {
      // The whole point. There is no limit, so nothing runs out and
      // nothing turns red.
      final long = at(const Duration(hours: 3, minutes: 12, seconds: 5));
      expect(long.elapsedLabel, '3:12:05');
      expect(long.elapsed.inHours, 3);
    });

    test('pads the seconds so the number does not jump about', () {
      expect(at(const Duration(minutes: 1, seconds: 5)).elapsedLabel, '01:05');
    });
  });
}
