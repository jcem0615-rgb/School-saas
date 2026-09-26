import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';

/// The rule that decides whether a lesson lives or is torn down.
///
/// It was backwards once, and the cost was the class watching Jitsi
/// announce "you have been disconnected" -- which it had been, by this
/// app, twenty seconds into a join that was simply slow.
void main() {
  group('whether a meeting is worth keeping', () {
    test('a joined conference is kept', () {
      expect(meetingIsWorthKeeping(anySignal: true, joined: true), isTrue);
    });

    test('a frame that has spoken is kept even if it has not joined yet', () {
      // This is the whole fix. A cold room on a distant server, from a
      // school's connection, is slow rather than broken, and a live
      // call is Jitsi's to manage -- its own reconnection notice beats
      // a screen that gives up on the lesson.
      expect(meetingIsWorthKeeping(anySignal: true, joined: false), isTrue);
    });

    test('a frame that has never said anything is not', () {
      // A deployment that refuses to be embedded is silent: no event of
      // any kind, ever. That one is worth taking down, because nothing
      // is coming.
      expect(meetingIsWorthKeeping(anySignal: false, joined: false), isFalse);
    });

    test('joined outranks silence, because joining is a signal', () {
      // Defensive: the two cannot disagree in practice, and if they
      // ever do, being in the room wins over not having noticed.
      expect(meetingIsWorthKeeping(anySignal: false, joined: true), isTrue);
    });
  });
}
