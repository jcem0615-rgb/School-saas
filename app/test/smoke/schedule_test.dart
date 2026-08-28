import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/schedules/domain/entities/schedule_block.dart';
import 'package:logicclass/features/schedules/presentation/controllers/schedule_controller.dart';
import 'package:logicclass/features/schedules/presentation/screens/my_timetable_screen.dart';

/// The unit tests check the arithmetic. These check that the arithmetic
/// is actually in the write path -- a clash check the save does not
/// consult is a clash check that does nothing.
Future<ProviderContainer> _signedInAs(UserRole role) async {
  final container = ProviderContainer(overrides: demoOverrides());
  container.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('the seeded week has no clashes in it', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final blocks = container.read(demoStoreProvider).scheduleBlocks.value;

    expect(blocks, isNotEmpty, reason: 'seed precondition');
    for (final block in blocks) {
      final conflicts = findConflicts(block, blocks.where((b) => b.id != block.id));
      expect(
        conflicts,
        isEmpty,
        // A demo that opens on a double-booked timetable reads as a bug
        // rather than as the feature working.
        reason: '${block.subject} ${block.section} ${block.dayLabel} clashes: '
            '${conflicts.map((c) => c.message).join(' ')}',
      );
    }
  });

  test('a class can be added and shows up on the section timetable', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final sub = container.listen(scheduleActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final year = store.scheduleBlocks.value.first.schoolYear;

    final ok = await container.read(scheduleActionControllerProvider.notifier).save(
          subject: 'Filipino',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          room: 'Room 201',
          dayOfWeek: 1,
          startMinute: 10 * 60,
          endMinute: 11 * 60,
          schoolYear: year,
          existing: store.scheduleBlocks.value,
        );

    expect(ok, isTrue);
    expect(
      store.scheduleBlocks.value.where((b) => b.subject == 'Filipino'),
      hasLength(1),
    );
  });

  test('the teacher clash is refused, and nothing is written', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    // The message is collected from the listener rather than read back
    // afterwards. In demo mode every repository watches authStateProvider
    // so that a role switch re-subscribes each stream, which also means
    // the autoDispose controller is rebuilt shortly after a write and
    // reads back as a fresh AsyncData. The screen sees the error because
    // it listens; a later read does not.
    final seen = <Object>[];
    final sub = container.listen(scheduleActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) seen.add(error);
    });
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final existing = store.scheduleBlocks.value.first;
    final before = store.scheduleBlocks.value.length;

    // Same teacher, same slot, a different section and room -- so the
    // only thing wrong with it is that she cannot be in two rooms.
    final ok = await container.read(scheduleActionControllerProvider.notifier).save(
          subject: 'Filipino',
          section: 'Grade 9 - Mabini',
          teacherId: existing.teacherId,
          teacherName: existing.teacherName,
          room: 'Room 105',
          dayOfWeek: existing.dayOfWeek,
          startMinute: existing.startMinute,
          endMinute: existing.endMinute,
          schoolYear: existing.schoolYear,
          existing: store.scheduleBlocks.value,
        );

    expect(ok, isFalse);
    expect(store.scheduleBlocks.value, hasLength(before));
    expect(seen.single.toString(), contains('already teaching'));
  });

  // The client check is a courtesy; the repository is what a callable
  // stands in for, and it has to refuse the same write.
  test('the repository refuses a clash even when the screen does not check', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);
    final existing = store.scheduleBlocks.value.first;

    final result = await container.read(scheduleRepositoryProvider).saveScheduleBlock(
          subject: 'Filipino',
          section: existing.section,
          teacherId: 'u_faculty_2',
          teacherName: 'Dennis Pascual',
          room: 'Room 999',
          dayOfWeek: existing.dayOfWeek,
          startMinute: existing.startMinute,
          endMinute: existing.endMinute,
          schoolYear: existing.schoolYear,
        );

    expect(result.isError, isTrue);
    expect(result.failureOrNull?.message, contains('already has a class'));
  });

  test('a class can be moved without clashing with its own old slot', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final sub = container.listen(scheduleActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final existing = store.scheduleBlocks.value.first;

    final ok = await container.read(scheduleActionControllerProvider.notifier).save(
          blockId: existing.id,
          subject: existing.subject,
          section: existing.section,
          teacherId: existing.teacherId,
          teacherName: existing.teacherName,
          room: existing.room,
          dayOfWeek: existing.dayOfWeek,
          // Ten minutes later, which still overlaps where it was.
          startMinute: existing.startMinute + 10,
          endMinute: existing.endMinute + 10,
          schoolYear: existing.schoolYear,
          existing: store.scheduleBlocks.value,
        );

    expect(ok, isTrue);
    final moved = store.scheduleBlocks.value.firstWhere((b) => b.id == existing.id);
    expect(moved.startMinute, existing.startMinute + 10);
  });

  test('removing a class takes it off the timetable', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final sub = container.listen(scheduleActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final existing = store.scheduleBlocks.value.first;

    expect(
      await container.read(scheduleActionControllerProvider.notifier).delete(existing.id),
      isTrue,
    );
    expect(store.scheduleBlocks.value.where((b) => b.id == existing.id), isEmpty);
  });

  test('a student sees their own section and nobody else\'s', () async {
    final container = await _signedInAs(UserRole.student);
    addTearDown(container.dispose);
    // Warm the stream the section provider reads from.
    await container.read(scheduleProvider.future);

    final mine = container.read(sectionScheduleProvider('Grade 10 - Rizal'));
    expect(mine, isNotEmpty);
    expect(mine.every((b) => b.section == 'Grade 10 - Rizal'), isTrue);
  });

  group('nextClassToday', () {
    final monday = [
      ScheduleBlock(
        id: 'a',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        teacherId: 't',
        teacherName: 'T',
        dayOfWeek: 1,
        startMinute: 7 * 60 + 30,
        endMinute: 8 * 60 + 30,
        schoolYear: '2026-2027',
      ),
      ScheduleBlock(
        id: 'b',
        subject: 'Science',
        section: 'Grade 10 - Rizal',
        teacherId: 't',
        teacherName: 'T',
        dayOfWeek: 1,
        startMinute: 8 * 60 + 40,
        endMinute: 9 * 60 + 40,
        schoolYear: '2026-2027',
      ),
    ];

    // 2026-08-31 is a Monday.
    test('names the class already under way, not the one after it', () {
      final next = nextClassToday(monday, now: DateTime(2026, 8, 31, 8, 0));
      expect(next?.subject, 'Mathematics');
    });

    test('moves on once a class has ended', () {
      final next = nextClassToday(monday, now: DateTime(2026, 8, 31, 8, 35));
      expect(next?.subject, 'Science');
    });

    // "Your next class is on Monday", shown at four o'clock on a Friday,
    // is noise.
    test('says nothing once the day is over', () {
      expect(nextClassToday(monday, now: DateTime(2026, 8, 31, 17, 0)), isNull);
    });

    test('says nothing on a day with no classes', () {
      expect(nextClassToday(monday, now: DateTime(2026, 9, 1, 8, 0)), isNull);
    });
  });
}
