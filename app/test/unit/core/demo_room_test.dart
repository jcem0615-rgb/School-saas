import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/demo_room.dart';

/// The demo's room names, against the rule that actually judges them.
///
/// This is the bug this file exists for: the demo generated
/// `lc-room_0001…` -- an underscore, and a counter rather than a secret
/// -- while the token endpoint accepted only the server's real format.
/// Every request was refused, and the app reported that live video was
/// not switched on. Two pieces of code in two languages disagreeing
/// about the shape of an identifier, with nothing holding them
/// together.
///
/// So the test reads the endpoint's own regular expression out of the
/// JavaScript and judges the Dart by it. Change either side and this
/// fails, which is the point.
void main() {
  /// The pattern the deployed endpoint enforces, taken from the file
  /// rather than copied -- a copy is the thing that drifts.
  RegExp endpointPattern() {
    final source = File('../vercel/api/livekit-token.js').readAsStringSync();
    final declaration =
        RegExp(r'const ROOM = /(.+?)/;').firstMatch(source);
    expect(declaration, isNotNull,
        reason: 'the endpoint no longer declares ROOM as a regex literal');
    return RegExp(declaration!.group(1)!);
  }

  group('a demo room name', () {
    test('is accepted by the endpoint that mints passes for it', () {
      final pattern = endpointPattern();
      for (var i = 0; i < 200; i++) {
        final room = newDemoMeetingRoom();
        expect(pattern.hasMatch(room), isTrue,
            reason: '$room would be refused with 400');
      }
    });

    test('is different every time', () {
      // A room reused across lessons is a door last term's leaver still
      // has a key to.
      final seen = {for (var i = 0; i < 500; i++) newDemoMeetingRoom()};
      expect(seen.length, 500);
    });

    test('is not a counter, which is what it used to be', () {
      // `room_0001`, `room_0002`. The room name is the whole of what
      // keeps somebody out of a lesson, and a demo shown to schools
      // should not teach that it is guessable.
      final a = newDemoMeetingRoom();
      final b = newDemoMeetingRoom();
      expect(a.substring(3), isNot(b.substring(3)));
      expect(a, isNot(contains('_')));

      // Two counters differ in a character or two at the end. Two
      // secrets differ nearly everywhere. Counting the positions is
      // the property; looking for a run of digits was a guess at it,
      // and a wrong one -- four digits fall next to each other in a
      // random name about one time in eight, so the test failed on
      // names that were perfectly good.
      var same = 0;
      for (var i = 3; i < a.length; i++) {
        if (a[i] == b[i]) same++;
      }
      expect(same, lessThan((a.length - 3) / 2));
    });

    test('says nothing about the class it belongs to', () {
      // It sits in an address bar and in whatever anybody pastes into a
      // chat.
      final room = newDemoMeetingRoom();
      expect(room.toLowerCase(), isNot(contains('grade')));
      expect(room.toLowerCase(), isNot(contains('math')));
      expect(room.toLowerCase(), isNot(contains('room')));
    });
  });
}
