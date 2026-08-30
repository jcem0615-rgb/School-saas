import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/class_sessions/domain/entities/class_session.dart';
import 'package:logicclass/features/class_sessions/presentation/controllers/class_session_controller.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/schedules/domain/entities/schedule_block.dart';

/// Taking a class register: Time In, mark the exceptions, Time Out.
///
/// Runs against the demo repositories, which mirror the three callables.
/// That does not prove the deployed functions behave the same -- only a
/// deployment can -- but it does pin the behaviour the two agree on, and
/// each rule here is one the server enforces too.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  /// A class on the teacher's timetable *today*, whichever day the test
  /// runs. The seeded timetable is Monday to Friday, so a suite run on a
  /// Saturday would otherwise have nothing to open and would pass by
  /// testing nothing.
  ScheduleBlock addTodaysClass(DemoStore store, {String subject = 'Mathematics'}) {
    final block = ScheduleBlock(
      id: 'sched_today_$subject',
      subject: subject,
      section: 'Grade 10 - Rizal',
      teacherId: 'u_faculty',
      teacherName: 'Maria Santos',
      room: 'Room 201',
      dayOfWeek: DateTime.now().weekday,
      startMinute: 7 * 60 + 30,
      endMinute: 8 * 60 + 30,
      schoolYear: '${DateTime.now().year}-${DateTime.now().year + 1}',
    );
    store.prepend(store.scheduleBlocks, block);
    return block;
  }

  /// The action controller, held open.
  ///
  /// Riverpod disposes a StateNotifier the moment nothing listens to it,
  /// and these controllers set state after an await -- so a test that
  /// only read the notifier would tear it down mid-write and fail on a
  /// disposed notifier rather than on the behaviour under test.
  ClassSessionActionController actions(ProviderContainer container) {
    final sub = container.listen(classSessionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(classSessionActionControllerProvider.notifier);
  }

  List<SubjectAttendanceMark> rollOf(DemoStore store, String sessionId) =>
      store.subjectAttendance.value.where((m) => m.sessionId == sessionId).toList();

  group('Time In', () {
    test('opens a register with everyone present', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final block = addTodaysClass(store);

      final sessionId = await actions(container).openSession(block.id);
      expect(sessionId, isNotNull);

      final roll = rollOf(store, sessionId!);
      // Marking a register is marking exceptions: three taps for three
      // absences, not forty taps for a full class.
      expect(roll, isNotEmpty);
      expect(roll.every((m) => m.status == AttendanceStatus.present), isTrue);
      expect(roll.every((m) => m.timeIn != null), isTrue);
      expect(roll.every((m) => m.timeOut == null), isTrue);

      // Only the section's enrolled students, not the whole school.
      final expected = store.students.value
          .where((s) =>
              s.section == 'Grade 10 - Rizal' && s.status.value == 'enrolled')
          .length;
      expect(roll.length, expected);
    });

    test('pressing it twice does not open a second register', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final block = addTodaysClass(store);
      final controller = actions(container);

      final first = await controller.openSession(block.id);
      // The teacher has already marked somebody absent by the time the
      // second press lands. Rebuilding the roll would wipe that.
      final victim = rollOf(store, first!).first;
      await controller.mark(
        sessionId: first,
        studentId: victim.studentId,
        status: AttendanceStatus.absent,
      );

      final second = await controller.openSession(block.id);
      expect(second, first);
      expect(
        store.classSessions.value.where((s) => s.id == first).length,
        1,
      );
      expect(
        rollOf(store, first)
            .firstWhere((m) => m.studentId == victim.studentId)
            .status,
        AttendanceStatus.absent,
      );
    });

    test('refuses a class that is not timetabled today', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final controller = actions(container);

      // A block on some other day. A stale "today's classes" list, or a
      // phone that slept through midnight, would otherwise file a day's
      // marks under the wrong date.
      final otherDay = DateTime.now().weekday == 1 ? 2 : 1;
      store.prepend(
        store.scheduleBlocks,
        ScheduleBlock(
          id: 'sched_not_today',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          dayOfWeek: otherDay,
          startMinute: 7 * 60 + 30,
          endMinute: 8 * 60 + 30,
          schoolYear: '2026-2027',
        ),
      );

      final sessionId = await controller.openSession('sched_not_today');
      expect(sessionId, isNull);
      expect(controller.errorMessage, contains('not timetabled today'));
    });
  });

  group('marking', () {
    test('changes one student and leaves the rest alone', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final block = addTodaysClass(store);
      final controller = actions(container);

      final sessionId = (await controller.openSession(block.id))!;
      final roll = rollOf(store, sessionId);
      final absent = roll[0];
      final late = roll[1];

      await controller.mark(
        sessionId: sessionId,
        studentId: absent.studentId,
        status: AttendanceStatus.absent,
      );
      await controller.mark(
        sessionId: sessionId,
        studentId: late.studentId,
        status: AttendanceStatus.late,
      );

      final after = rollOf(store, sessionId);
      final counts = RollCounts.of(after);
      expect(counts.absent, 1);
      expect(counts.late, 1);
      expect(counts.present, after.length - 2);
      expect(counts.total, after.length);

      // An absent student has no time in, because they were not there.
      expect(
        after.firstWhere((m) => m.studentId == absent.studentId).timeIn,
        isNull,
      );
      expect(
        after.firstWhere((m) => m.studentId == late.studentId).timeIn,
        isNotNull,
      );
    });

    test('refuses to rewrite an earlier day\'s register', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final controller = actions(container);

      // The seeded registers all come from previous days.
      final old = store.classSessions.value.first;
      final mark = rollOf(store, old.id).first;
      final ok = await controller.mark(
        sessionId: old.id,
        studentId: mark.studentId,
        status: AttendanceStatus.absent,
      );

      expect(ok, isFalse);
      expect(controller.errorMessage, contains('earlier day'));
      expect(
        rollOf(store, old.id)
            .firstWhere((m) => m.studentId == mark.studentId)
            .status,
        mark.status,
      );
    });
  });

  group('Time Out', () {
    test('stamps a finish on everyone who was there, and nobody who was not',
        () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final block = addTodaysClass(store);
      final controller = actions(container);

      final sessionId = (await controller.openSession(block.id))!;
      final away = rollOf(store, sessionId).first.studentId;
      await controller.mark(
        sessionId: sessionId,
        studentId: away,
        status: AttendanceStatus.absent,
      );

      expect(await controller.closeSession(sessionId), isTrue);

      final after = rollOf(store, sessionId);
      for (final mark in after) {
        if (mark.studentId == away) {
          // No time out, because there was no time in.
          expect(mark.timeOut, isNull);
        } else {
          expect(mark.timeOut, isNotNull);
          expect(mark.minutes, isNotNull);
        }
      }

      final session =
          store.classSessions.value.firstWhere((s) => s.id == sessionId);
      expect(session.isOpen, isFalse);
      expect(session.counts?.absent, 1);
      expect(session.minutes, isNotNull);
    });

    test('a correction after Time Out keeps the summary honest', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final block = addTodaysClass(store);
      final controller = actions(container);

      final sessionId = (await controller.openSession(block.id))!;
      await controller.closeSession(sessionId);
      final before = store.classSessions.value
          .firstWhere((s) => s.id == sessionId)
          .counts!;
      expect(before.absent, 0);

      // Time Out means "the class is over", not "this is now history".
      final student = rollOf(store, sessionId).first.studentId;
      expect(
        await controller.mark(
          sessionId: sessionId,
          studentId: student,
          status: AttendanceStatus.absent,
        ),
        isTrue,
      );

      final after =
          store.classSessions.value.firstWhere((s) => s.id == sessionId).counts!;
      expect(after.absent, 1);
      expect(after.present, before.present - 1);
    });
  });

  group('what a family sees', () {
    test('groups a term by subject, worst first', () async {
      final container = await signedInAs(UserRole.parent);
      final sub = container.listen(
        studentSubjectMarksProvider('stu_001'),
        (_, __) {},
      );
      addTearDown(sub.close);
      await container.read(studentSubjectMarksProvider('stu_001').future);

      final summaries =
          container.read(studentSubjectSummaryProvider('stu_001'));
      expect(summaries, isNotEmpty);

      // The reason anybody opens this screen is to find the subject that
      // is going wrong, so it is first.
      expect(summaries.first.subject, 'Science');
      expect(summaries.first.attendanceRate, lessThan(0.75));

      // And it is a rate over lessons held, not over lessons attended.
      for (final summary in summaries) {
        expect(summary.counts.total, greaterThan(0));
        expect(summary.counts.attended, lessThanOrEqualTo(summary.counts.total));
      }
    });

    test('an excused absence still counts as a lesson missed', () async {
      final container = await signedInAs(UserRole.parent);
      final sub = container.listen(
        studentSubjectMarksProvider('stu_001'),
        (_, __) {},
      );
      addTearDown(sub.close);
      await container.read(studentSubjectMarksProvider('stu_001').future);

      final science = container
          .read(studentSubjectSummaryProvider('stu_001'))
          .firstWhere((s) => s.subject == 'Science');

      // A school that quietly dropped excused lessons from the
      // denominator would report a child who missed half a term with a
      // note as having a perfect record.
      expect(science.counts.excused, greaterThan(0));
      expect(
        science.counts.total,
        science.counts.present +
            science.counts.late +
            science.counts.absent +
            science.counts.excused,
      );
    });
  });
}
