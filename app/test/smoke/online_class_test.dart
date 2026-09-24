import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/class_sessions/domain/entities/class_session.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import 'package:logicclass/features/class_sessions/presentation/controllers/class_session_controller.dart';
import 'package:logicclass/features/class_sessions/presentation/screens/class_roll_screen.dart';
import 'package:logicclass/features/class_sessions/presentation/screens/todays_classes_screen.dart';
import 'package:logicclass/features/faculty_portal/presentation/screens/faculty_dashboard_screen.dart';

/// Holding a lesson online, and shutting the door afterwards.
///
/// The room name is the whole of the security -- anyone holding it is in
/// a video call with a class of children -- so most of what is pinned
/// here is about when it exists and when it stops existing.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    // The schedule and the register are streams; the providers below
    // read them synchronously and would see an empty list on the frame
    // the sign-in lands.
    final sub = c.listen(classSessionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return c;
  }

  ClassSessionActionController actions(ProviderContainer c) =>
      c.read(classSessionActionControllerProvider.notifier);

  /// Starts today's first class and returns its session id.
  ///
  /// The listener is not decoration: `myClassesTodayProvider` is
  /// autoDispose over a stream, so reading it with nobody subscribed
  /// disposes it before the schedule has emitted and it answers "no
  /// classes" forever.
  Future<String> openAClass(ProviderContainer c) async {
    final held = c.listen(myClassesTodayProvider, (_, __) {});
    addTearDown(held.close);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final blocks = c.read(myClassesTodayProvider);
    expect(blocks, isNotEmpty, reason: 'the demo needs a class on today');
    final id = await actions(c).openSession(blocks.first.id);
    expect(id, isNotNull);
    return id!;
  }

  ClassSession sessionOf(ProviderContainer c, String id) =>
      c.read(demoStoreProvider).classSessions.value.firstWhere((s) => s.id == id);

  List<SubjectAttendanceMark> rollOf(ProviderContainer c, String id) => c
      .read(demoStoreProvider)
      .subjectAttendance
      .value
      .where((m) => m.sessionId == id)
      .toList();

  group('taking the class online', () {
    test('gives it a room, and puts it on every student in it', () async {
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);

      final room = await actions(c).setMode(sessionId: id, online: true);

      expect(room, isNotNull);
      expect(sessionOf(c, id).meetingRoom, room);
      final roll = rollOf(c, id);
      expect(roll, isNotEmpty);
      // The student reads the room off their own mark, never off the
      // session: classSessions is staff-only in firestore.rules and
      // holding a class online did not widen that.
      expect(roll.every((m) => m.meetingRoom == room), isTrue);
    });

    test('and the class reads as live only while it is both', () async {
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      expect(sessionOf(c, id).isOnlineNow, isFalse);

      await actions(c).setMode(sessionId: id, online: true);
      expect(sessionOf(c, id).isOnlineNow, isTrue);
    });

    test('a different room every time, never a reused one', () async {
      // A room kept across lessons is a door last term's leaver still
      // has a key to.
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);

      final first = await actions(c).setMode(sessionId: id, online: true);
      final second = await actions(c).setMode(sessionId: id, online: true);

      expect(second, isNot(first));
      expect(rollOf(c, id).every((m) => m.meetingRoom == second), isTrue,
          reason: 'a link copied a minute ago must not still be live');
    });

    test('the room says nothing about the class', () async {
      // The name is in the address bar of every participant. One naming
      // the school, the section or the subject discloses all three to
      // anyone who ever sees the link.
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      final session = sessionOf(c, id);

      final room = (await actions(c).setMode(sessionId: id, online: true))!;

      expect(room.toLowerCase(), isNot(contains(session.section.toLowerCase())));
      expect(room.toLowerCase(), isNot(contains(session.subject.toLowerCase())));
      expect(room, isNot(contains(session.date)));
    });
  });

  group('shutting the door', () {
    test('coming back in person closes the room', () async {
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      await actions(c).setMode(sessionId: id, online: true);

      await actions(c).setMode(sessionId: id, online: false);

      expect(sessionOf(c, id).meetingRoom, isNull);
      expect(rollOf(c, id).every((m) => m.meetingRoom == null), isTrue);
      expect(sessionOf(c, id).isOnlineNow, isFalse);
    });

    test('and so does Time Out', () async {
      // Without this the lesson ends, the teacher leaves, and a class of
      // children is in an unsupervised video call reachable from a
      // register that says the class is over.
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      await actions(c).setMode(sessionId: id, online: true);

      expect(await actions(c).closeSession(id), isTrue);

      expect(sessionOf(c, id).meetingRoom, isNull);
      expect(rollOf(c, id).every((m) => m.meetingRoom == null), isTrue);
    });

    test('including for a student who was never in the lesson', () async {
      // Absent students get no time out, which is why their mark is
      // worth checking separately -- a child who was not there must not
      // be left holding the way in either.
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      final absentee = rollOf(c, id).first;
      await actions(c).mark(
        sessionId: id,
        studentId: absentee.studentId,
        status: AttendanceStatus.absent,
      );
      await actions(c).setMode(sessionId: id, online: true);
      await actions(c).closeSession(id);

      final after =
          rollOf(c, id).firstWhere((m) => m.studentId == absentee.studentId);
      expect(after.meetingRoom, isNull);
      expect(after.timeOut, isNull, reason: 'they had no time in');
    });

    test('a finished class cannot be taken online', () async {
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      await actions(c).closeSession(id);

      final room = await actions(c).setMode(sessionId: id, online: true);

      expect(room, isNull);
      expect(actions(c).errorMessage, contains('already finished'));
    });
  });

  group('what the student is shown', () {
    test('nothing at all when no class is online', () async {
      final c = await signedInAs(UserRole.student);
      final student = c.read(demoStoreProvider).students.value.first;
      final held = c.listen(myOnlineClassProvider(student.id), (_, __) {});
      addTearDown(held.close);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.read(myOnlineClassProvider(student.id)), isNull);
    });

    test('the live lesson once their teacher starts it', () async {
      final teacher = await signedInAs(UserRole.faculty);
      final id = await openAClass(teacher);
      final room = await actions(teacher).setMode(sessionId: id, online: true);
      final onTheRoll = rollOf(teacher, id).first;

      // The same store, read as the student it belongs to.
      teacher.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student),
          );
      final held =
          teacher.listen(myOnlineClassProvider(onTheRoll.studentId), (_, __) {});
      addTearDown(held.close);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final live = teacher.read(myOnlineClassProvider(onTheRoll.studentId));
      expect(live, isNotNull);
      expect(live!.meetingRoom, room);
      expect(live.hasOnlineClass, isTrue);
    });

    test('and nothing again once the lesson ends', () async {
      final c = await signedInAs(UserRole.faculty);
      final id = await openAClass(c);
      await actions(c).setMode(sessionId: id, online: true);
      final onTheRoll = rollOf(c, id).first;
      final held =
          c.listen(myOnlineClassProvider(onTheRoll.studentId), (_, __) {});
      addTearDown(held.close);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.read(myOnlineClassProvider(onTheRoll.studentId)), isNotNull);

      await actions(c).closeSession(id);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(c.read(myOnlineClassProvider(onTheRoll.studentId)), isNull);
    });
  });

  group('the control the teacher uses', () {
    /// Signs in and seeds a register with no real-clock waiting.
    ///
    /// Every demo write sleeps to imitate a round trip, and every helper
    /// above awaits one. That is right in a plain `test()` and fatal in
    /// `testWidgets`: the widget clock stands still while a real-clock
    /// delay never completes, so the test hangs until the runner kills
    /// it. Nothing here awaits anything the widget clock has to drive.
    ({ProviderContainer container, String sessionId}) registerOn({String? room}) {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      c.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
          );

      final store = c.read(demoStoreProvider);
      const id = 'sess_widget_test';
      final today = DateTime.now().toIso8601String().substring(0, 10);

      store.classSessions.add([
        ClassSession(
          id: id,
          scheduleBlockId: 'sched_001',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          date: today,
          teacherName: 'Maria Santos',
          takenByUid: 'u_faculty',
          takenByName: 'Maria Santos',
          openedAt: DateTime.now(),
          studentCount: 1,
          meetingRoom: room,
        ),
        ...store.classSessions.value.where((s) => s.id != id),
      ]);
      // A roll as well as the session: an empty one leaves the screen on
      // its spinner, and a spinner schedules frames forever.
      store.subjectAttendance.add([
        SubjectAttendanceMark(
          id: '${id}_stu_001',
          sessionId: id,
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          date: today,
          status: AttendanceStatus.present,
          meetingRoom: room,
        ),
        ...store.subjectAttendance.value.where((m) => m.sessionId != id),
      ]);

      return (container: c, sessionId: id);
    }

    /// A narrow phone with large text -- the hardest case this bar has,
    /// and the one a teacher holding a handset in front of a class is
    /// actually in.
    Future<void> pumpRegister(
        WidgetTester tester, ProviderContainer c, String sessionId) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: ClassRollScreen(sessionId: sessionId),
          ),
        ),
      ));
      // Fixed frames rather than pumpAndSettle: the screen carries
      // progress indicators, and a continuous animation means there is
      // always another frame scheduled.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('offers to take the class online, and fits a phone',
        (tester) async {
      final r = registerOn();

      await pumpRegister(tester, r.container, r.sessionId);

      expect(find.text('Take online'), findsOneWidget);
      expect(find.text('This class is in the room.'), findsOneWidget);
      // The whole point of the Wrap: a control that holds a lesson must
      // not be clipped off the edge of the card.
      expect(tester.takeException(), isNull);
    });

    testWidgets('and once it is online, offers Join and End', (tester) async {
      final r = registerOn(room: 'lc-abcdefghijklmnopqrst');

      await pumpRegister(tester, r.container, r.sessionId);

      expect(find.text('Join'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.textContaining('Everyone on the register can join'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('finding it in the first place', () {
    testWidgets('the faculty dashboard has a way in', (tester) async {
      // It was reachable only through Class Attendance -> the day's list
      // -> Time In -> the register. That is a path nobody guesses at on
      // the morning classes are suspended.
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      c.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
          );

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: FacultyDashboardScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Online Class'), findsOneWidget);
    });

    testWidgets('and the day list offers to start one on every class',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      c.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
          );

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: TodaysClassesScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // One tap, not three: a lesson cannot be held online without a
      // register, so the button opens the session, takes it online and
      // goes in. The teacher should not have to know that order.
      expect(find.text('Start online class'), findsWidgets);
      expect(find.text('Time in'), findsWidgets);
      // And it fits a phone rather than clipping the control that
      // starts the lesson off the edge of the card.
      expect(tester.takeException(), isNull);
    });
  });
}
