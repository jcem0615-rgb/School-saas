import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';
import 'package:logicclass/core/meeting/meeting_surface.dart';
import 'package:logicclass/core/meeting/online_class_screen.dart';

/// The embedded path, which no test could reach before.
///
/// It shipped a screen that spun forever: the meeting view -- the thing
/// that creates the element Jitsi attaches to -- was only built once the
/// meeting had started, and the meeting could not start until the
/// element existed. Every one of these tests fails against that version.
class _FakeSurface extends MeetingSurface {
  _FakeSurface({
    this.prepareResult = true,
    this.hostResult = true,
    this.startResult = true,
    this.throwOnStart = false,
  });

  final bool prepareResult;
  final bool hostResult;
  final bool startResult;
  final bool throwOnStart;

  /// The order the screen does things in, which is where the bug was.
  final calls = <String>[];
  final commands = <String>[];

  /// Set when the screen actually builds the view. The element only
  /// exists because this was built, so "was it built before start" is
  /// the question.
  bool viewBuilt = false;
  bool viewBuiltBeforeStart = false;

  @override
  Future<bool> prepare() async {
    calls.add('prepare');
    return prepareResult;
  }

  @override
  Future<bool> awaitHost(String room) async {
    calls.add('awaitHost');
    return hostResult;
  }

  @override
  bool start({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
  }) {
    calls.add('start');
    viewBuiltBeforeStart = viewBuilt;
    if (throwOnStart) throw StateError('parentNode is null');
    return startResult;
  }

  @override
  void leave(String room) => calls.add('leave');

  @override
  void command(String room, String command) => commands.add(command);

  @override
  Widget view(String room) {
    viewBuilt = true;
    return const ColoredBox(color: Color(0xFF000000));
  }
}

class _EmbeddingLauncher extends MeetingLauncher {
  const _EmbeddingLauncher();

  @override
  MeetingSupport get support => MeetingSupport.embedded;

  @override
  Future<bool> handOff(String room, {required String displayName}) async => true;
}

Widget _screen(_FakeSurface surface) => MaterialApp(
      home: OnlineClassScreen(
        room: 'lc-abcdefghijklmnopqrst',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        displayName: 'Ms Santos',
        asModerator: true,
        openedAt: DateTime(2026, 9, 24, 8),
        scheduledMinutes: 60,
        debugSurface: surface,
        debugLauncher: const _EmbeddingLauncher(),
      ),
    );

/// Enough pumps for the awaits in _start to run, without
/// pumpAndSettle -- a CircularProgressIndicator never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the classroom cannot be left spinning', () {
    testWidgets('the view is built before the meeting is started', (tester) async {
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      // The element Jitsi attaches to exists only because the view was
      // built. Building it after start is the deadlock.
      expect(surface.viewBuiltBeforeStart, isTrue,
          reason: 'the meeting was started before its view existed');
      expect(surface.calls, <String>['prepare', 'awaitHost', 'start']);
    });

    testWidgets('a started meeting shows the classroom controls', (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface()));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('a script that will not load lands on the fallback', (tester) async {
      final surface = _FakeSurface(prepareResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Join the class'), findsWidgets);
      // Never asked to start something that could not be prepared.
      expect(surface.calls, <String>['prepare']);
    });

    testWidgets('a host element that never appears lands on the fallback',
        (tester) async {
      final surface = _FakeSurface(hostResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Join the class'), findsWidgets);
      expect(surface.calls, <String>['prepare', 'awaitHost']);
    });

    testWidgets('a throwing start lands on the fallback, not a spinner',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface(throwOnStart: true)));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Join the class'), findsWidgets);
    });

    testWidgets('a refused start lands on the fallback', (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface(startResult: false)));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Join the class'), findsWidgets);
    });
  });

  group('while it is connecting', () {
    testWidgets('it says what it is waiting for', (tester) async {
      // Never resolves within the pumps below, so the connecting state
      // is what is on screen.
      final surface = _SlowSurface();
      await tester.pumpWidget(MaterialApp(
        home: OnlineClassScreen(
          room: 'lc-abcdefghijklmnopqrst',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          displayName: 'Ms Santos',
          debugSurface: surface,
          debugLauncher: const _EmbeddingLauncher(),
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Connecting to the class'), findsOneWidget);
      expect(find.textContaining(meetingDomain), findsOneWidget);
      // And the view is already in the tree -- that is the whole point.
      expect(surface.viewBuilt, isTrue);
    });
  });

  group('leaving', () {
    testWidgets('hangs up before the screen goes away', (tester) async {
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      await tester.tap(find.text('Leave'));
      await tester.pump();

      expect(surface.commands, contains('hangup'));
    });
  });
}

/// A surface whose prepare never completes.
class _SlowSurface extends _FakeSurface {
  @override
  Future<bool> prepare() {
    calls.add('prepare');
    return Completer<bool>().future;
  }
}
