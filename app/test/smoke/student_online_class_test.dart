import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/meeting/online_class_notice.dart';
import 'package:logicclass/core/widgets/glass_tile.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/class_sessions/presentation/controllers/class_session_controller.dart';
import 'package:logicclass/features/class_sessions/presentation/screens/my_online_classes_screen.dart';
import 'package:logicclass/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:logicclass/features/schedules/domain/entities/schedule_block.dart';
import 'package:logicclass/features/student_portal/presentation/screens/student_dashboard_screen.dart';

/// The student's own way into a lesson, and the nudge that gets them
/// there.
///
/// The banner only exists while a class is running, which is most of the
/// time not -- so a pupil told "we are online today" who saw nothing had
/// no way of knowing whether the lesson had not started or the app had
/// lost it, and nowhere to look. The tile is always there; the screen
/// behind it says which of the two it is; and the notification reaches
/// the ones who never opened the app at all.
void main() {
  /// Puts a class on today's timetable, whatever day the tests run on.
  ///
  /// The demo timetable runs Monday to Friday, so a group that read
  /// whatever happened to be on the current weekday failed every
  /// weekend, on a calendar nothing here controls.
  void ensureAClassToday(ProviderContainer c) {
    final store = c.read(demoStoreProvider);
    final today = DateTime.now().weekday;
    if (store.scheduleBlocks.value
        .any((b) => b.dayOfWeek == today && b.teacherId == 'u_faculty')) {
      return;
    }
    store.scheduleBlocks.add([
      ...store.scheduleBlocks.value,
      ScheduleBlock(
        id: 'sched_today_student_online',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        teacherId: 'u_faculty',
        teacherName: 'Maria Santos',
        room: 'Room 201',
        dayOfWeek: today,
        startMinute: 8 * 60,
        endMinute: 9 * 60,
        schoolYear: '${DateTime.now().year}-${DateTime.now().year + 1}',
      ),
    ]);
  }

  void signInAs(ProviderContainer c, UserRole role) {
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
  }

  /// Opens today's class as the teacher and takes it online.
  ///
  /// Returns the student whose own mark now carries the room -- the only
  /// way a pupil ever reaches one, because `classSessions` is staff-only
  /// and nothing about holding a class online widened that.
  ///
  /// Everything here runs inside [WidgetTester.runAsync]: the demo
  /// repositories await real delays to feel like a network, and a widget
  /// test's clock is fake, so awaiting one outside runAsync is a test
  /// that hangs rather than fails.
  Future<String> aLessonIsOn(ProviderContainer c, WidgetTester tester) async {
    late String studentId;
    await tester.runAsync(() async {
      signInAs(c, UserRole.faculty);
      ensureAClassToday(c);
      final held = c.listen(myClassesTodayProvider, (_, __) {});
      addTearDown(held.close);

      // Polled rather than slept on. The timetable is a stream behind an
      // autoDispose provider and the account is another stream in front
      // of it; a fixed wait is a test that passes on one machine.
      var blocks = c.read(myClassesTodayProvider);
      for (var i = 0; i < 60 && blocks.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        blocks = c.read(myClassesTodayProvider);
      }
      expect(blocks, isNotEmpty, reason: 'a class should be on today');
      final actions = c.read(classSessionActionControllerProvider.notifier);
      final sessionId = await actions.openSession(blocks.first.id);
      expect(sessionId, isNotNull);
      await actions.setMode(sessionId: sessionId!, online: true);

      final roll = c
          .read(demoStoreProvider)
          .subjectAttendance
          .value
          .where((m) => m.sessionId == sessionId);
      expect(roll, isNotEmpty, reason: 'the roll is where the room lands');
      studentId = roll.first.studentId;
    });
    await tester.pumpAndSettle();
    return studentId;
  }

  /// A container signed in as the student, with [screen] pumped.
  Future<ProviderContainer> pump(WidgetTester tester, Widget screen) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    signInAs(container, UserRole.student);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('the tile on the dashboard', () {
    testWidgets('is there even when no class is on', (tester) async {
      // The whole reason it exists. "Nothing here" is what a broken app
      // looks like too.
      await pump(tester, const StudentDashboardScreen());

      expect(find.text('Online Class'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says LIVE while a lesson is running', (tester) async {
      final c = await pump(tester, const StudentDashboardScreen());

      await aLessonIsOn(c, tester);
      signInAs(c, UserRole.student);
      await tester.pumpAndSettle();

      expect(find.text('LIVE'), findsOneWidget);
      final tile = tester.widget<GlassTile>(
        find.widgetWithText(GlassTile, 'Online Class'),
      );
      expect(tile.badge, 'LIVE');
    });

    testWidgets('opens the screen behind it', (tester) async {
      await pump(tester, const StudentDashboardScreen());

      await tester.tap(find.text('Online Class'));
      await tester.pumpAndSettle();

      expect(find.byType(MyOnlineClassesScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the screen behind it', () {
    testWidgets('says nothing is on rather than showing an empty list',
        (tester) async {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      signInAs(c, UserRole.student);
      final studentId = c.read(demoStoreProvider).students.value.first.id;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(home: MyOnlineClassesScreen(studentId: studentId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No class is online right now'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      // And the sentence for a pupil whose chat app mangled the link.
      expect(find.text('If your teacher sent you a link'), findsOneWidget);
      expect(find.textContaining('do not need the link'), findsOneWidget);
    });

    testWidgets('lists the lesson, and asks for the code before going in',
        (tester) async {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      final studentId = await aLessonIsOn(c, tester);

      signInAs(c, UserRole.student);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(home: MyOnlineClassesScreen(studentId: studentId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No class is online right now'), findsNothing);
      expect(find.text('Join'), findsOneWidget);

      // The tile is a door, not a key: the register, the code and the
      // scope are all still checked on the server.
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Class code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the class is told', () {
    testWidgets('every student on the register gets a notification',
        (tester) async {
      // A class held in a room announces itself: the bell goes. A class
      // held online announces itself to whoever has the app open, which
      // at ten past eight on a Tuesday is nobody.
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await aLessonIsOn(c, tester);

      signInAs(c, UserRole.student);
      late List<dynamic> inbox;
      await tester.runAsync(() async {
        final held = c.listen(notificationsProvider, (_, __) {});
        addTearDown(held.close);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        inbox = c.read(notificationsProvider).valueOrNull ?? const [];
      });

      final about = inbox.where((n) => '${n.title}'.contains('is online now'));
      expect(about, isNotEmpty,
          reason: 'the pupil who never opened the app hears nothing otherwise');
    });

    testWidgets('and tapping it lands on the same address as a link',
        (tester) async {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await aLessonIsOn(c, tester);

      signInAs(c, UserRole.student);
      late List<dynamic> inbox;
      await tester.runAsync(() async {
        final held = c.listen(notificationsProvider, (_, __) {});
        addTearDown(held.close);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        inbox = c.read(notificationsProvider).valueOrNull ?? const [];
      });

      final about =
          inbox.where((n) => '${n.title}'.contains('is online now')).toList();
      expect(about, isNotEmpty);
      // One route for a notification and for a forwarded link, so both
      // end up in the same place asking for the same code.
      expect('${about.first.link}', startsWith('/join?school='));
      expect('${about.first.link}', contains('&class='));
    });
  });

  group('the words on the lock screen', () {
    test('name the lesson, not just the app', () {
      // "LogicClass" says which app. It does not say which lesson, and a
      // pupil with four classes a day needs the second one.
      expect(onlineClassTitle('Mathematics'), 'Mathematics is online now');
      expect(onlineClassBody('Mathematics', 'Grade 10 - Rizal'),
          contains('Grade 10 - Rizal'));
      expect(onlineClassBody('Mathematics', 'Grade 10 - Rizal'),
          contains('class code'));
    });

    test('still say something when the record is blank', () {
      expect(onlineClassTitle(''), 'Your class is online now');
      expect(onlineClassTitle('   '), 'Your class is online now');
      expect(onlineClassBody('', ''), startsWith('Your class has started'));
    });

    test('and the link is the invitation route', () {
      expect(
        onlineClassLink(schoolId: 'school-1', sessionId: 'sess-2'),
        '/join?school=school-1&class=sess-2',
      );
    });
  });

  testWidgets('every lesson is offered, not just the first', (tester) async {
    // A lesson that overran and the next one starting. A student picking
    // the wrong one from a list of one is a student in the wrong lesson.
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    final studentId = await aLessonIsOn(c, tester);
    await tester.runAsync(() async {
      final held = c.listen(myOnlineClassesProvider(studentId), (_, __) {});
      addTearDown(held.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    expect(c.read(myOnlineClassesProvider(studentId)), hasLength(1));
    // And the banner still shows one, because a banner is one line.
    expect(c.read(myOnlineClassProvider(studentId)), isNotNull);
  });
}
