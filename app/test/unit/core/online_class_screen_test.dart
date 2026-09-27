import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';
import 'package:logicclass/features/class_sessions/data/datasources/class_session_remote_datasource.dart';
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
    this.joinedResult = true,
    this.aliveBeforeJoin = false,
    this.throwOnStart = false,
  });

  final bool prepareResult;
  final bool hostResult;
  final bool startResult;
  final bool joinedResult;

  /// The frame showed signs of running before it finished joining --
  /// a cold room on a distant server, which is slow and not broken.
  final bool aliveBeforeJoin;
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

  /// What the screen handed Jitsi. Null is the unconfigured school.
  String? startedWithToken;

  @override
  bool start({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
    String? token,
  }) {
    calls.add('start');
    startedWithToken = token;
    viewBuiltBeforeStart = viewBuilt;
    if (throwOnStart) throw StateError('parentNode is null');
    return startResult;
  }

  @override
  Future<bool> awaitJoined(String room, {void Function()? onAlive}) async {
    calls.add('awaitJoined');
    if (aliveBeforeJoin) onAlive?.call();
    return joinedResult;
  }

  @override
  void leave(String room) => calls.add('leave');

  @override
  void command(String room, String command) => commands.add(command);

  /// How many times the screen has asked for the meeting widget.
  ///
  /// The number that matters. Each rebuild of the subtree holding a
  /// platform view is a chance for Flutter to reparent its host element,
  /// and a browser reloads an iframe that moves in the DOM.
  int viewBuilds = 0;

  @override
  Widget view(String room) {
    viewBuilt = true;
    viewBuilds++;
    return const ColoredBox(color: Color(0xFF000000));
  }
}

class _EmbeddingLauncher extends MeetingLauncher {
  const _EmbeddingLauncher();

  @override
  MeetingSupport get support => MeetingSupport.embedded;

  @override
  Future<bool> handOff(
    String room, {
    required String displayName,
    String? token,
    bool muted = false,
  }) async =>
      true;
}

Widget _screen(_FakeSurface surface, {String? token}) => MaterialApp(
      home: OnlineClassScreen(
        room: 'lc-abcdefghijklmnopqrst',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        displayName: 'Ms Santos',
        token: token,
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
      expect(surface.calls,
          <String>['prepare', 'awaitHost', 'start', 'awaitJoined']);
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
      expect(find.text('Try joining again'), findsWidgets);
      // Never asked to start something that could not be prepared.
      expect(surface.calls, <String>['prepare']);
    });

    testWidgets('a host element that never appears lands on the fallback',
        (tester) async {
      final surface = _FakeSurface(hostResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try joining again'), findsWidgets);
      expect(surface.calls, <String>['prepare', 'awaitHost']);
    });

    testWidgets('a throwing start lands on the fallback, not a spinner',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface(throwOnStart: true)));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try joining again'), findsWidgets);
    });

    testWidgets('a refused start lands on the fallback', (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface(startResult: false)));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try joining again'), findsWidgets);
    });
  });

  group('the pass that replaces the sign-in', () {
    testWidgets('is handed to the meeting', (tester) async {
      // Without it the lesson opens onto Jitsi's own sign-in, and a
      // ten-year-old is asked for a Google account to attend their own
      // school's class.
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface, token: 'header.claims.signature'));
      await _settle(tester);

      expect(surface.startedWithToken, 'header.claims.signature');
    });

    testWidgets('is absent, not empty, when the school has no key',
        (tester) async {
      // An unconfigured school joins without one. An empty string is
      // not the same thing: Jitsi reads it as a token and rejects it.
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(surface.startedWithToken, isNull);
    });
  });

  group('nobody waits out the timeout', () {
    /// A deployment that refuses to be framed takes the full timeout to
    /// say so. A class should not spend it watching a spinner with
    /// nothing to press.
    Widget slow() => MaterialApp(
          home: OnlineClassScreen(
            room: 'lc-abcdefghijklmnopqrst',
            subject: 'Mathematics',
            section: 'Grade 10 - Rizal',
            displayName: 'Ms Santos',
            debugSurface: _SlowSurface(),
            debugLauncher: const _EmbeddingLauncher(),
          ),
        );

    testWidgets('the way out is not offered straight away', (tester) async {
      // Shown immediately it reads as an expectation of failure, on a
      // lesson that is simply taking four seconds.
      await tester.pumpWidget(slow());
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Try joining again'), findsNothing);
      expect(find.text('Connecting to the class'), findsOneWidget);
    });

    testWidgets('it appears once this has gone on too long', (tester) async {
      await tester.pumpWidget(slow());
      await tester.pump(const Duration(seconds: 8));

      expect(find.text('Try joining again'), findsOneWidget);
      // Still trying underneath -- this is an offer, not a surrender.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('taking it tears the dead frame out first', (tester) async {
      // Retrying on top of a half-built frame is how two connections to
      // the same room appear.
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
      await tester.pump(const Duration(seconds: 8));
      await tester.tap(find.text('Try joining again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(surface.calls, contains('leave'));
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

  group('a meeting that has not spoken to us', () {
    testWidgets('is kept, not torn down', (tester) async {
      // Jitsi's events only start once the app inside the iframe has
      // downloaded itself -- megabytes, from a server that may be a
      // continent away. Silence means "still coming", and ending the
      // lesson over it is how a working class was stopped.
      final surface = _FakeSurface(joinedResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(surface.calls, isNot(contains('leave')));
      expect(find.text('Leave'), findsOneWidget);
      expect(surface.viewBuilt, isTrue);
    });

    testWidgets('says so over the meeting, and offers another go',
        (tester) async {
      final surface = _FakeSurface(joinedResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.textContaining('has not started the class inside the app'),
          findsOneWidget);
      // Names what actually fixes it, rather than asking a teacher to
      // keep pressing a button that cannot help -- and says it in words
      // meant for somebody in front of a class, not a file path.
      expect(find.textContaining('the school needs its own video server'),
          findsOneWidget);
      expect(find.textContaining('docs/'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a meeting that does speak says nothing of the kind',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeSurface(joinedResult: true)));
      await _settle(tester);

      expect(find.textContaining('has not started the class inside the app'),
          findsNothing);
      expect(find.text('Leave'), findsOneWidget);
    });
  });

  group('a slow join is not a dead one', () {
    testWidgets('the meeting takes the screen as soon as it is alive',
        (tester) async {
      // The overlay used to sit on top of a working call until it had
      // joined, and then tear the call down if that took too long. The
      // class watched Jitsi announce a disconnection this app had
      // caused.
      final surface = _FakeSurface(aliveBeforeJoin: true, joinedResult: true);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.text('Connecting to the class'), findsNothing);
      expect(find.text('Leave'), findsOneWidget);
      expect(surface.calls, isNot(contains('leave')));
    });

    testWidgets('and it is on screen before any event at all', (tester) async {
      // The reveal moved ahead of the join. Waiting for a first event
      // kept the class off a meeting that was merely still loading.
      final surface = _FakeSurface(aliveBeforeJoin: false, joinedResult: false);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.text('Connecting to the class'), findsNothing);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('a live frame that never finishes joining is still kept',
        (tester) async {
      // Alive but not joined is Jitsi's problem to narrate, not this
      // screen's to end. Nothing may be disposed.
      final surface = _FakeSurface(aliveBeforeJoin: true, joinedResult: true);
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      expect(find.text('Try joining again'), findsNothing);
      expect(surface.calls, isNot(contains('leave')));
    });
  });

  group('the clock must not touch the meeting', () {
    testWidgets('a minute of ticks rebuilds no part of the call',
        (tester) async {
      // This is the disconnection. The clock ran setState(() {}) on a
      // one-second timer, rebuilding the whole screen -- the Stack, and
      // with it the platform view holding Jitsi's iframe. A browser
      // reloads an iframe that is moved in the DOM. The lesson was
      // being re-scened once a second on a connection that was fine.
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      final afterJoin = surface.viewBuilds;
      for (var second = 0; second < 60; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(surface.viewBuilds, afterJoin,
          reason: 'the meeting was rebuilt by the clock');
    });

    testWidgets('the clock is fed by a notifier, not by setState',
        (tester) async {
      // The structural half of the same fix, and the one a future edit
      // is most likely to undo: the clock must reach the screen through
      // something only the control bar listens to. Put it back on the
      // State and everything above rebuilds with it, the meeting
      // included.
      //
      // (Its ticking cannot be asserted here -- the label comes from
      // DateTime.now(), and a widget test's real clock does not move.
      // What the clock reads is class_clock_test's job.)
      await tester.pumpWidget(_screen(_FakeSurface()));
      await _settle(tester);

      expect(find.text('CLASS TIME'), findsOneWidget);
      expect(find.byType(ValueListenableBuilder<DateTime>), findsOneWidget);
    });

    testWidgets('and pressing Mute does not rebuild the call either',
        (tester) async {
      final surface = _FakeSurface();
      await tester.pumpWidget(_screen(surface));
      await _settle(tester);

      final afterJoin = surface.viewBuilds;
      await tester.tap(find.text('Mute'));
      await tester.pump();

      expect(find.text('Unmute'), findsOneWidget);
      expect(surface.viewBuilds, afterJoin);
      expect(surface.commands, contains('toggleAudio'));
    });
  });

  group('a class can always leave the loading screen', () {
    /// The screen that prompted this: "Connecting to the class", and it
    /// stayed there. Every path through _start is bounded and it still
    /// happened, so reasoning about the bounds was not enough.
    Widget stuck(_SlowSurface surface) => MaterialApp(
          home: OnlineClassScreen(
            room: 'lc-abcdefghijklmnopqrst',
            subject: 'Mathematics',
            section: 'Grade 10 - Rizal',
            displayName: 'Ms Santos',
            debugSurface: surface,
            debugLauncher: const _EmbeddingLauncher(),
          ),
        );

    testWidgets('a step that never returns still ends in the card',
        (tester) async {
      final surface = _SlowSurface();
      await tester.pumpWidget(stuck(surface));
      await tester.pump(const Duration(seconds: 45));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try joining again'), findsWidgets);
      // And the dead frame is not left in the page.
      expect(surface.calls, contains('leave'));
    });

    testWidgets('the card says where it gave up', (tester) async {
      // So a screenshot of the failure is a bug report rather than
      // another round of guessing.
      await tester.pumpWidget(stuck(_SlowSurface()));
      await tester.pump(const Duration(seconds: 45));

      expect(find.textContaining('Gave up'), findsOneWidget);
      expect(find.textContaining('loading the video service'), findsOneWidget);
    });

    testWidgets('while it waits it names the step and counts the seconds',
        (tester) async {
      // "Loading" is equally true of a script that will never arrive, a
      // frame that cannot exist, and a room that is simply slow. Three
      // problems, three answers, one word on screen.
      await tester.pumpWidget(stuck(_SlowSurface()));
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining('Loading the video service'), findsOneWidget);
      expect(find.textContaining('3s'), findsOneWidget);
    });
  });

  _notDeployed();

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

/// The window between deploying the site and deploying the functions.
///
/// The two ship separately, and in that window the app asks for a token
/// from a callable that is not there. Turning that into a refusal would
/// stop every lesson in the school -- strictly worse than the sign-in
/// this feature removes.
void _notDeployed() {
  group('a token callable that is not deployed yet', () {
    test('is not treated as a refusal', () {
      expect(ClassSessionRemoteDataSource.meansNotDeployed('not-found'), isTrue);
      expect(ClassSessionRemoteDataSource.meansNotDeployed('unimplemented'), isTrue);
    });

    test('is told apart from every refusal we actually issue', () {
      // These are answers to be shown to somebody, not gaps to paper
      // over: a child who is not on the register must be told so.
      for (final code in const [
        'permission-denied',
        'failed-precondition',
        'unauthenticated',
        'invalid-argument',
        'internal',
        'unavailable',
      ]) {
        expect(ClassSessionRemoteDataSource.meansNotDeployed(code), isFalse,
            reason: '$code is a real answer and must reach the person');
      }
    });
  });
}
