import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/class_clock.dart';

/// A class has a bell. A video call does not, and a lesson held in one
/// runs over because nobody in it can see the clock the timetable keeps.
void main() {
  final start = DateTime(2026, 9, 24, 7, 30);
  ClassClock at(Duration into, {int? minutes = 60}) => ClassClock(
        openedAt: start,
        now: start.add(into),
        scheduledMinutes: minutes,
      );

  group('what it counts', () {
    test('elapsed, from when the teacher pressed Time In', () {
      expect(at(const Duration(minutes: 12, seconds: 7)).elapsedLabel, '12:07');
    });

    test('and never backwards when the device clock is behind', () {
      // A phone a few seconds behind the server would otherwise show a
      // class that has not started yet.
      final behind = ClassClock(
        openedAt: start,
        now: start.subtract(const Duration(seconds: 30)),
        scheduledMinutes: 60,
      );
      expect(behind.elapsed, Duration.zero);
      expect(behind.elapsedLabel, '00:00');
    });

    test('past an hour it grows an hours field', () {
      // And minutes stay two digits either way, so the number does not
      // jump width as it counts.
      expect(at(const Duration(hours: 1, minutes: 7, seconds: 2)).elapsedLabel,
          '1:07:02');
      expect(at(const Duration(minutes: 7, seconds: 2)).elapsedLabel, '07:02');
    });
  });

  group('what is left', () {
    test('is said in words, not left as arithmetic', () {
      expect(at(const Duration(seconds: 9)).remainingLabel,
          '59:51 left of 60 minutes.');
    });

    test('floors at zero rather than counting backwards', () {
      final over = at(const Duration(minutes: 75));
      expect(over.remaining, Duration.zero);
      expect(over.progress, 1.0);
    });

    test('and says so once the slot is used up', () {
      // The class does not stop -- ending it is the teacher's decision,
      // not a timer's -- but nobody should have to work out that they
      // are over.
      expect(at(const Duration(minutes: 60, seconds: 5)).overrunning, isTrue);
      expect(at(const Duration(minutes: 60, seconds: 5)).remainingLabel,
          'The 60 minutes are up.');
      expect(at(const Duration(minutes: 68)).remainingLabel,
          '08:00 past the 60 minutes.');
    });

    test('is not claimed at all when the length is unknown', () {
      // A student's classroom knows when the lesson started but not what
      // the timetable gives it. Saying "no set length" would be a claim
      // about the timetable rather than about what the screen can see.
      final unknown = at(const Duration(minutes: 5), minutes: null);
      expect(unknown.remainingLabel, isNull);
      expect(unknown.progress, isNull);
      expect(unknown.scheduledLabel, isNull);
      expect(unknown.overrunning, isFalse);
      // The half it does know still works.
      expect(unknown.elapsedLabel, '05:00');
    });
  });

  group('the bar', () {
    test('runs nought to one across the lesson', () {
      expect(at(Duration.zero).progress, 0.0);
      expect(at(const Duration(minutes: 30)).progress, 0.5);
      expect(at(const Duration(minutes: 60)).progress, 1.0);
    });

    test('and a zero-length class does not divide by it', () {
      expect(at(const Duration(minutes: 5), minutes: 0).progress, isNull);
    });
  });
}
