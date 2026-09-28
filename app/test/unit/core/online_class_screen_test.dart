import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/board_controller.dart';
import 'package:logicclass/core/meeting/camera_setup.dart';
import 'package:logicclass/core/meeting/hands.dart';
import 'package:logicclass/core/meeting/online_class_screen.dart';
import 'package:logicclass/core/meeting/whiteboard.dart';
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

  /// What the browser's own chooser did. A teacher who cancels it has
  /// shared nothing, whatever the button asked for.
  bool shareAccepted = true;
  bool sharing = false;
  int shareAsks = 0;

  List<CameraOption> available = const [
    CameraOption(id: 'built-in', label: 'Integrated Webcam'),
    CameraOption(id: 'usb-1', label: 'Logitech C920'),
  ];
  String? cameraUsed;
  BackgroundSupport blurResult = BackgroundSupport.available;
  bool? blurWanted;
  final sent = <BoardMessage>[];
  LessonBoard? board;

  final signalled = <Signal>[];
  final lowered = <String?>[];
  final roster = ValueNotifier<List<Attendee>>(const []);

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
  Future<bool> setScreenShare(bool on) async {
    shareAsks++;
    sharing = on && shareAccepted;
    return sharing;
  }

  @override
  Future<List<CameraOption>> cameras() async => available;

  @override
  Future<void> useCamera(String deviceId) async => cameraUsed = deviceId;

  @override
  Future<BackgroundSupport> setBackgroundBlur(bool on) async {
    blurWanted = on;
    return blurResult;
  }

  @override
  Future<void> sendBoardMessage(BoardMessage message) async =>
      sent.add(message);

  @override
  void attachBoard(LessonBoard board) => this.board = board;

  @override
  Future<void> signal(Signal signal) async => signalled.add(signal);

  @override
  Future<void> lowerHands({String? identity}) async => lowered.add(identity);

  @override
  ValueListenable<List<Attendee>> get attendees => roster;

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

Attendee _attendee(String id, String name, {bool handUp = false}) => Attendee(
      identity: id,
      name: name,
      isMe: false,
      joinedAt: DateTime.now(),
      micOn: true,
      cameraOn: true,
      signal: handUp
          ? Signal(handRaisedAt: DateTime.now().subtract(const Duration(minutes: 2)))
          : Signal.none,
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

    testWidgets('sharing puts a window up, and says so', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      await tester.tap(find.text('Share screen'));
      await _settle(tester);

      expect(call.sharing, isTrue);
      expect(find.text('Stop sharing'), findsOneWidget);
    });

    testWidgets('sharing says nothing was shared when the teacher cancels',
        (tester) async {
      // The browser shows its own chooser. A button that then sat there
      // saying "Stop sharing" would be lying about the state of the
      // lesson.
      final call = _FakeCall()..shareAccepted = false;
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      await tester.tap(find.text('Share screen'));
      await _settle(tester);

      expect(call.shareAsks, 1);
      expect(find.text('Share screen'), findsOneWidget);
      expect(find.text('Stop sharing'), findsNothing);
    });

    testWidgets('the pencil appears with the screen it draws on',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      // Offered over a lesson with nothing shared, it would draw on
      // nothing -- and a tool that does nothing when pressed is a tool
      // a teacher stops trusting.
      expect(find.text('Pencil'), findsNothing);

      await tester.tap(find.text('Share screen'));
      await _settle(tester);

      expect(find.text('Pencil'), findsOneWidget);
      expect(find.text('Eraser'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('the pencil is put away with the screen', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);
      await tester.tap(find.text('Share screen'));
      await _settle(tester);
      await tester.tap(find.text('Pencil'));
      await _settle(tester);
      expect(call.board!.tool, BoardTool.pencil);

      await tester.tap(find.text('Stop sharing'));
      await _settle(tester);

      // Otherwise the next person to share would find a pencil already
      // in their hand.
      expect(call.board!.tool, BoardTool.off);
      expect(find.text('Pencil'), findsNothing);
    });

    testWidgets('a pupil is offered no pencil at all', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);
      await tester.tap(find.text('Share screen'));
      await _settle(tester);

      expect(find.text('Pencil'), findsNothing);
      expect(call.board!.canDraw, isFalse);
    });

    testWidgets('the board reaches the call, so the class can see it',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      // The call is what puts a stroke on the wire and what hands an
      // arriving one back. A board the call has never been given is a
      // teacher drawing to themselves.
      expect(call.board, isNotNull);
      call.board!
        ..choose(BoardTool.pencil)
        ..startAt(const Offset(0.2, 0.2))
        ..extendTo(const Offset(0.8, 0.8))
        ..finish();

      expect(call.sent.single, isA<MarkDrawn>());
    });

    testWidgets('clearing is not offered while there is nothing to clear',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);
      await tester.tap(find.text('Share screen'));
      await _settle(tester);

      final clear = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Clear'),
      );
      expect(clear.onPressed, isNull);
    });

    testWidgets('the camera panel offers what is plugged in', (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      await tester.tap(find.text('Camera'));
      await _settle(tester);

      expect(find.text('Integrated Webcam'), findsOneWidget);
      expect(find.text('Logitech C920'), findsOneWidget);

      await tester.tap(find.text('Logitech C920'));
      await _settle(tester);

      // Mid-lesson, without rejoining: a teacher who has to leave the
      // lesson to change camera has left the lesson.
      expect(call.cameraUsed, 'usb-1');
    });

    testWidgets('the blur switch believes the camera, not the request',
        (tester) async {
      // Browsers accept this request and then leave the picture exactly
      // as it was. A switch sitting in the "on" position over an
      // unchanged background is worse than one that admits it cannot.
      final call = _FakeCall()..blurResult = BackgroundSupport.unavailable;
      await tester.pumpWidget(_screen(call));
      await _settle(tester);
      await tester.tap(find.text('Camera'));
      await _settle(tester);

      await tester.tap(find.text('Blur my background'));
      await _settle(tester);

      expect(call.blurWanted, isTrue);
      final blur = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Blur my background'),
      );
      expect(blur.value, isFalse);
      expect(find.textContaining('not from LogicClass'), findsOneWidget);
    });

    testWidgets('a pupil can put a hand up, and take it down',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);

      await tester.tap(find.text('Raise hand'));
      await _settle(tester);

      expect(call.signalled.last.handIsUp, isTrue);
      expect(find.text('Hand down'), findsOneWidget);

      await tester.tap(find.text('Hand down'));
      await _settle(tester);

      expect(call.signalled.last.handIsUp, isFalse);
      expect(find.text('Raise hand'), findsOneWidget);
    });

    testWidgets('a pupil can answer without unmuting', (tester) async {
      // Sixty microphones opening at once is not a lesson.
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);

      await tester.tap(find.text(Reaction.yes.glyph));
      await _settle(tester);

      expect(call.signalled.last.reaction, Reaction.yes);
    });

    testWidgets('and a reaction does not take their hand down',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);

      await tester.tap(find.text('Raise hand'));
      await _settle(tester);
      await tester.tap(find.text(Reaction.no.glyph));
      await _settle(tester);

      // Two different things being said. Answering a question is not
      // withdrawing a request to speak.
      expect(call.signalled.last.handIsUp, isTrue);
      expect(call.signalled.last.reaction, Reaction.no);
    });

    testWidgets('the teacher takes hands rather than raising one',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      expect(find.text('Raise hand'), findsNothing);
      expect(find.text(Reaction.yes.glyph), findsNothing);
    });

    testWidgets('the class button counts the room, and then the hands',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);

      call.roster.value = [
        _attendee('a', 'Ana'),
        _attendee('b', 'Ben'),
      ];
      await _settle(tester);
      expect(find.text('Class · 2'), findsOneWidget);

      call.roster.value = [
        _attendee('a', 'Ana', handUp: true),
        _attendee('b', 'Ben'),
      ];
      await _settle(tester);

      // A hand up is the thing being waited on, so it is what the
      // button says.
      expect(find.text('Class · 1 up'), findsOneWidget);
    });

    testWidgets('the class list names who is here and who put a hand up',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);
      call.roster.value = [
        _attendee('a', 'Ana Cruz', handUp: true),
        _attendee('b', 'Ben Reyes'),
      ];
      await _settle(tester);

      await tester.tap(find.textContaining('Class ·'));
      await _settle(tester);

      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Ben Reyes'), findsOneWidget);
      expect(find.textContaining('1 hand up'), findsOneWidget);
    });

    testWidgets('and lets the teacher take one down, or all of them',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call));
      await _settle(tester);
      call.roster.value = [_attendee('a', 'Ana Cruz', handUp: true)];
      await _settle(tester);
      await tester.tap(find.textContaining('Class ·'));
      await _settle(tester);

      await tester.tap(find.text('Lower'));
      await _settle(tester);
      expect(call.lowered.last, 'a');

      await tester.tap(find.text('Lower 1'));
      await _settle(tester);
      // Null is everybody: nobody can reach into somebody else's
      // attributes, so each device lowers its own when it sees this.
      expect(call.lowered.last, isNull);
    });

    testWidgets('a pupil is not offered a way to lower anybody\'s hand',
        (tester) async {
      final call = _FakeCall();
      await tester.pumpWidget(_screen(call, asModerator: false));
      await _settle(tester);
      call.roster.value = [_attendee('a', 'Ana Cruz', handUp: true)];
      await _settle(tester);

      await tester.tap(find.textContaining('Class ·'));
      await _settle(tester);

      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Lower'), findsNothing);
      expect(find.textContaining('Lower 1'), findsNothing);
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
