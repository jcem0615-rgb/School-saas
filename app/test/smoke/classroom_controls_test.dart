import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/meeting/online_class_screen.dart';
import 'package:logicclass/core/meeting/webrtc/classroom_call.dart';

/// The classroom at the width a child actually holds.
///
/// The controls are the app's own, under the call, and they are
/// labelled: a row of bare icons is a row a ten-year-old has to guess
/// at, in the middle of a lesson.
class _StillCall implements ClassroomCall {
  @override
  Future<bool> join({
    required String url,
    required String token,
    required bool asModerator,
  }) async =>
      true;

  @override
  Future<void> leave() async {}

  @override
  Future<void> setMicrophone(bool on) async {}

  @override
  Future<void> setCamera(bool on) async {}

  @override
  Widget view() => const ColoredBox(color: Color(0xFF101010));
}

void main() {
  Future<void> pumpClassroom(WidgetTester tester) async {
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
          token: 'a.b.c',
          asModerator: true,
          provider: 'livekit',
          serverUrl: 'wss://school.livekit.cloud',
          openedAt: DateTime.now().subtract(const Duration(minutes: 9)),
          debugCall: _StillCall(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the class it is opens the screen, named', (tester) async {
    await pumpClassroom(tester);
    // A teacher takes the same subject four times over and needs to
    // know which one they are in.
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Grade 10 - Rizal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 360px screen at 1.3x text without clipping',
      (tester) async {
    // The width and text size a school phone actually has. Leave is the
    // control that must never be the one pushed off the edge.
    await pumpClassroom(tester);

    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Camera off'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows how long the lesson has run, and no deadline',
      (tester) async {
    await pumpClassroom(tester);

    expect(find.text('CLASS TIME'), findsOneWidget);
    expect(find.textContaining('09:'), findsOneWidget);
    // No limit: a lesson is not over because an hour passed.
    expect(find.textContaining('left of'), findsNothing);
  });
}
