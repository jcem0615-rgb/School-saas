import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/schedules/domain/entities/schedule_block.dart';

/// Clash detection is the whole feature, and all of it is arithmetic, so
/// all of it is checkable here.

ScheduleBlock block({
  String id = 'b1',
  String subject = 'Mathematics',
  String section = 'Grade 10 - Rizal',
  String teacherId = 'u_faculty',
  String teacherName = 'Maria Santos',
  String? room = 'Room 201',
  int day = 1,
  int start = 450, // 7:30
  int end = 510, // 8:30
  String schoolYear = '2026-2027',
}) =>
    ScheduleBlock(
      id: id,
      subject: subject,
      section: section,
      teacherId: teacherId,
      teacherName: teacherName,
      room: room,
      dayOfWeek: day,
      startMinute: start,
      endMinute: end,
      schoolYear: schoolYear,
    );

void main() {
  group('overlap', () {
    // Every timetable in the country is written back-to-back. Calling
    // this a clash would make the feature unusable on day one.
    test('touching ends do not overlap', () {
      final first = block(start: 450, end: 510);
      final second = block(id: 'b2', start: 510, end: 570);
      expect(first.overlaps(second), isFalse);
      expect(second.overlaps(first), isFalse);
    });

    test('a partial overlap is an overlap, from either side', () {
      final first = block(start: 450, end: 510);
      final second = block(id: 'b2', start: 500, end: 560);
      expect(first.overlaps(second), isTrue);
      expect(second.overlaps(first), isTrue);
    });

    test('a class wholly inside another overlaps it', () {
      final outer = block(start: 450, end: 570);
      final inner = block(id: 'b2', start: 480, end: 500);
      expect(outer.overlaps(inner), isTrue);
      expect(inner.overlaps(outer), isTrue);
    });

    test('the same slot on a different day does not overlap', () {
      expect(block(day: 1).overlaps(block(id: 'b2', day: 2)), isFalse);
    });
  });

  group('findConflicts', () {
    test('catches a teacher in two places at once', () {
      final conflicts = findConflicts(
        block(id: '', section: 'Grade 9 - Mabini', room: 'Room 105'),
        [block(id: 'b1')],
      );
      expect(conflicts.map((c) => c.kind), [ScheduleClash.teacher]);
    });

    test('catches a section booked twice', () {
      final conflicts = findConflicts(
        block(id: '', teacherId: 'u_other', teacherName: 'Someone Else', room: 'Room 105'),
        [block(id: 'b1')],
      );
      expect(conflicts.map((c) => c.kind), [ScheduleClash.section]);
    });

    test('catches a room booked twice', () {
      final conflicts = findConflicts(
        block(
          id: '',
          teacherId: 'u_other',
          teacherName: 'Someone Else',
          section: 'Grade 9 - Mabini',
        ),
        [block(id: 'b1')],
      );
      expect(conflicts.map((c) => c.kind), [ScheduleClash.room]);
    });

    // An admin who fixes the room only to be told about the teacher has
    // been made to do the work twice for nothing.
    test('reports every clash at once, not the first', () {
      final conflicts = findConflicts(block(id: ''), [block(id: 'b1')]);
      expect(
        conflicts.map((c) => c.kind).toSet(),
        {ScheduleClash.teacher, ScheduleClash.section, ScheduleClash.room},
      );
    });

    // Punishing schools that do not timetable rooms would make the
    // feature useless to most of them.
    test('two classes with no room recorded are not in the same room', () {
      final conflicts = findConflicts(
        block(id: '', teacherId: 'u_other', section: 'Grade 9 - Mabini', room: null),
        [block(id: 'b1', room: null)],
      );
      expect(conflicts, isEmpty);
    });

    test('a blank room is treated as no room', () {
      final conflicts = findConflicts(
        block(id: '', teacherId: 'u_other', section: 'Grade 9 - Mabini', room: '   '),
        [block(id: 'b1', room: '')],
      );
      expect(conflicts, isEmpty);
    });

    test('rooms and sections match regardless of case and padding', () {
      final conflicts = findConflicts(
        block(id: '', teacherId: 'u_other', section: '  grade 10 - rizal ', room: ' ROOM 201 '),
        [block(id: 'b1')],
      );
      expect(
        conflicts.map((c) => c.kind).toSet(),
        {ScheduleClash.section, ScheduleClash.room},
      );
    });

    // Editing a block must not clash with the copy of itself on file.
    test('a block does not clash with itself', () {
      expect(findConflicts(block(id: 'b1'), [block(id: 'b1')]), isEmpty);
    });

    test('last year\'s timetable does not clash with this year\'s', () {
      final conflicts = findConflicts(
        block(id: '', schoolYear: '2027-2028'),
        [block(id: 'b1', schoolYear: '2026-2027')],
      );
      expect(conflicts, isEmpty);
    });

    test('a conflict names the class it is with', () {
      final conflicts = findConflicts(block(id: ''), [block(id: 'b1', subject: 'Science')]);
      expect(conflicts.first.message, contains('Science'));
      expect(conflicts.first.message, contains('Maria Santos'));
      expect(conflicts.first.message, contains('Monday'));
    });
  });

  group('time formatting', () {
    test('formats noon and midnight the way a clock does', () {
      expect(formatMinuteOfDay(0), '12:00 AM');
      expect(formatMinuteOfDay(12 * 60), '12:00 PM');
      expect(formatMinuteOfDay(13 * 60 + 5), '1:05 PM');
      expect(formatMinuteOfDay(7 * 60 + 30), '7:30 AM');
    });

    test('reads back what a person is likely to type', () {
      expect(parseMinuteOfDay('7:30 AM'), 7 * 60 + 30);
      expect(parseMinuteOfDay('7:30am'), 7 * 60 + 30);
      expect(parseMinuteOfDay('1:05 PM'), 13 * 60 + 5);
      expect(parseMinuteOfDay('13:05'), 13 * 60 + 5);
      expect(parseMinuteOfDay('1330'), 13 * 60 + 30);
      expect(parseMinuteOfDay('7'), 7 * 60);
      expect(parseMinuteOfDay('12:00 AM'), 0);
      expect(parseMinuteOfDay('12:30 PM'), 12 * 60 + 30);
    });

    test('refuses what is not a time', () {
      expect(parseMinuteOfDay(''), isNull);
      expect(parseMinuteOfDay('lunch'), isNull);
      expect(parseMinuteOfDay('25:00'), isNull);
      expect(parseMinuteOfDay('7:75'), isNull);
    });

    test('round-trips every minute of the day', () {
      for (var minute = 0; minute < 24 * 60; minute++) {
        expect(parseMinuteOfDay(formatMinuteOfDay(minute)), minute,
            reason: 'failed at ${formatMinuteOfDay(minute)}');
      }
    });
  });
}
