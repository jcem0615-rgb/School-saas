import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/online_class_screen.dart';
import 'package:logicclass/core/meeting/webrtc/classroom_call.dart';

/// The classroom, driven without opening a camera.
///
/// The seam exists because every version of this screen that a test
/// could not reach shipped a bug a test would have caught -- twice a
/// screen that believed something it had never checked.
class _FakeCall implements ClassroomCall {
  _FakeCall({this.joins = true, this.failure});

  final bool joins;
  final String? failure;

  @override
  String? lastError;
  final calls = <String>[];
  bool? micWanted;
  bool? cameraWanted;
  bool joinedAsModerator = false;
  int views = 0;

  @override
  Future<bool> join({
    required String url,
    required String token,
    required bool asModerator,
  }) async {
    calls.add('join');
    joinedAsModerator = asModerator;
    if (!joins) lastError = failure;
    return joins;
  }

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  Future<void> setMicrophone(bool on) async => micWanted = on;

  @override
  Future<void> setCamera(bool on) async => cameraWanted = on;

  @override
  Widget view() {
    views++;
    return const ColoredBox(color: Color(0xFF101010));
  }
}

Widget _screen(
  _FakeCall call, {
  bool asModerator = true,
  String provider = 'livekit',
  String? url = 'wss://school.livekit.cloud',
  String? token = 'a.b.c',
  Future<String?> Function()? configuration,
}) =>
    MaterialApp(
      home: OnlineClassScreen(
        room: 'lc-abcdefghijklmnopqrst',
        subject: 'English',
        section: 'Grade 10 - Rizal',
        displayName: 'Ms Santos',
        token: token,
        provider: provider,
        serverUrl: url,
        asModerator: asModerator,
        openedAt: DateTime.now().subtract(const Duration(minutes: 90)),
        debugCall: call,
        debugConfiguration: configuration,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('joining', () {
    testWidgets('shows the lesson once it is in', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      expect(call.calls, contains('join'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('a refused join offers another go rather than a spinner',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeCall(joins: false)));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try joining again'), findsOneWidget);
    });

    testWidgets('and says what the server actually said', (tester) async {
      // The two ways this goes wrong -- an address that is https where
      // it should be wss, and a key the server rejects -- both read as
      // "could not start". Whoever is configuring it should not have to
      // open a browser console to tell them apart.
      await tester.pumpWidget(_screen(
        _FakeCall(joins: false, failure: 'ConnectException: invalid token'),
      ));
      await _settle(tester);

      expect(find.textContaining('invalid token'), findsOneWidget);
    });

    testWidgets('and puts the endpoint\'s own account of itself on the card',
        (tester) async {
      // `invalid token` means the three LiveKit values are present and
      // wrong, which is the one thing the endpoint cannot see while it
      // is minting. A GET on it says which are the wrong shape -- but
      // only if somebody opens it, and the person looking at a failed
      // demo should not have to. So the card asks, and says.
      await tester.pumpWidget(_screen(
        _FakeCall(joins: false, failure: 'ConnectException: invalid token'),
        configuration: () async =>
            'LIVEKIT_API_KEY and LIVEKIT_API_SECRET look swapped.',
      ));
      await _settle(tester);

      expect(find.textContaining('look swapped'), findsOneWidget);
      expect(find.textContaining('invalid token'), findsOneWidget);
    });

    testWidgets('and says nothing when the endpoint will not account for itself',
        (tester) async {
      await tester.pumpWidget(_screen(
        _FakeCall(joins: false, failure: 'ConnectException: invalid token'),
        configuration: () async => null,
      ));
      await _settle(tester);

      // A card that fails to reach its own endpoint says what it knows
      // and no more. An empty box under the error is worse than none.
      expect(find.text('Try joining again'), findsOneWidget);
      expect(find.textContaining('LIVEKIT_'), findsNothing);
    });

    testWidgets('and asks again on the next attempt, not once a lesson',
        (tester) async {
      var asked = 0;
      await tester.pumpWidget(_screen(
        _FakeCall(joins: false, failure: 'ConnectException: invalid token'),
        configuration: () async {
          asked += 1;
          return 'LIVEKIT_API_SECRET is 6 characters.';
        },
      ));
      await _settle(tester);
      expect(asked, 1);

      await tester.tap(find.text('Try joining again'));
      await _settle(tester);

      // The point of retrying is usually that something was changed in
      // between. A stale answer from before the change is worse than
      // asking twice.
      expect(asked, 2);
      expect(find.textContaining('6 characters'), findsOneWidget);
    });

    testWidgets('and says nothing extra when there is nothing to add',
        (tester) async {
      await tester.pumpWidget(_screen(_FakeCall(joins: false)));
      await _settle(tester);

      expect(find.text('Try joining again'), findsOneWidget);
    });

    testWidgets('the teacher arrives speaking', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: true));
      await _settle(tester);

      expect(call.joinedAsModerator, isTrue);
      // The control agrees with the state it arrived in: a Mute button
      // on somebody who is already muted is a teacher talking to
      // nobody.
      expect(find.text('Mute'), findsOneWidget);
    });

    testWidgets('everybody else arrives quiet', (tester) async {
      // Sixty microphones opening at once is how an online lesson
      // starts badly.
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);

      expect(call.joinedAsModerator, isFalse);
      expect(find.text('Unmute'), findsOneWidget);
    });
  });

  group('when the school has no video server', () {
    testWidgets('it says so instead of trying anyway', (tester) async {
      // There used to be a fallback here that sent the class at an
      // embedded meeting which could not work. Saying nothing is set
      // up beats breaking a lesson to prove it.
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, provider: 'none', url: null));
      await _settle(tester);

      expect(call.calls, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Tests run with DEMO_MODE at its default, so this is the
      // demo's wording. It must not send somebody off to configure a
      // school that does not exist.
      expect(find.textContaining('demo'), findsWidgets);
      expect(find.textContaining('The school needs to connect'), findsNothing);
    });

    testWidgets('and a pass without a server is not enough either',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, provider: 'livekit', url: null));
      await _settle(tester);

      expect(call.calls, isEmpty);
    });

    testWidgets('nor a server without a pass', (tester) async {
      // A media server that let anybody in would be a room of children
      // reachable by whoever guessed a name.
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, token: null));
      await _settle(tester);

      expect(call.calls, isEmpty);
    });
  });

  group('the controls', () {
    testWidgets('mute and camera reach the call and change the label',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(call.micWanted, isFalse);
      expect(find.text('Unmute'), findsOneWidget);

      await tester.tap(find.text('Camera off'));
      await tester.pump();
      expect(call.cameraWanted, isFalse);
      expect(find.text('Camera on'), findsOneWidget);
    });

    testWidgets('leaving hangs up', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      await tester.tap(find.text('Leave'));
      await tester.pump();

      expect(call.calls, contains('leave'));
    });
  });

  group('the clock', () {
    testWidgets('counts up and never runs out', (tester) async {
      // Ninety minutes in. There is no limit and nothing to run out:
      // a lesson is not over because an hour passed.
      await tester.pumpWidget(_screen(_FakeCall()));
      await _settle(tester);

      expect(find.text('CLASS TIME'), findsOneWidget);
      expect(find.textContaining('1:30'), findsOneWidget);
      expect(find.textContaining('left of'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a minute of ticks never rebuilds the lesson', (tester) async {
      // Rebuilding the subtree that holds the video is how a working
      // class gets disconnected.
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      final afterJoin = call.views;
      for (var second = 0; second < 60; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(call.views, afterJoin, reason: 'the clock rebuilt the video');
    });
  });
}
