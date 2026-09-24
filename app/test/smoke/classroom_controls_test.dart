import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/meeting/class_clock.dart';
import 'package:logicclass/core/meeting/online_class_screen.dart';

/// The classroom's own controls, at the width a child actually holds.
///
/// They sit under the call rather than inside it: Jitsi's toolbar is in
/// the iframe and scales with it, and on a phone-width browser it
/// becomes a row of icons to guess at. These are labelled, and they
/// carry the one thing Jitsi cannot know -- how much of the lesson is
/// left.
void main() {
  Future<void> pumpClassroom(WidgetTester tester, {int? minutes}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: OnlineClassScreen(
          room: 'lc-abcdefghijklmnopqrst',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          displayName: 'Miguel Torres',
          openedAt: DateTime.now().subtract(const Duration(minutes: 9)),
          scheduledMinutes: minutes,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the class it is opens the screen, named', (tester) async {
    await pumpClassroom(tester, minutes: 60);
    // A teacher takes the same subject four times over and needs to know
    // which one they are in.
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Grade 10 - Rizal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('and offers a way in when the video cannot run here',
      (tester) async {
    // On the VM there is no browser and no SDK, so this is the
    // hand-off path -- which is what a desktop build does, and what any
    // platform falls back to when the call will not start. It must be a
    // way into the lesson, not a dead end.
    await pumpClassroom(tester, minutes: 60);
    expect(find.text('Join the class'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('the clock it shows', () {
    test('counts against the timetabled length', () {
      final start = DateTime(2026, 9, 24, 7, 30);
      final c = ClassClock(
        openedAt: start,
        now: start.add(const Duration(minutes: 9)),
        scheduledMinutes: 60,
      );
      expect(c.elapsedLabel, '09:00');
      expect(c.scheduledLabel, '1:00:00');
      expect(c.remainingLabel, '51:00 left of 60 minutes.');
    });

    test('and shows a student elapsed time with nothing invented', () {
      // A student's mark carries when the lesson started, not how long
      // the timetable gives it.
      final start = DateTime(2026, 9, 24, 7, 30);
      final c = ClassClock(
        openedAt: start,
        now: start.add(const Duration(minutes: 9)),
      );
      expect(c.elapsedLabel, '09:00');
      expect(c.remainingLabel, isNull);
    });
  });
}
