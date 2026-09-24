import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';

/// Where a school's children's lessons happen.
///
/// Pinned because it was wrong in a way nothing could see: the default
/// was a deployment that asks the first person in to sign in and will
/// not be embedded by another site, which produced a sign-in page,
/// "waiting for a moderator" and the lesson opening in a browser tab --
/// three complaints, one cause.
void main() {
  group('the deployment video classes are held on', () {
    test('is not the one that refuses to be embedded', () {
      // meet.jit.si requires the room's creator to authenticate and
      // pushes embedding to a paid product. "Inside the app" cannot be
      // true there.
      expect(meetingDomain, isNot('meet.jit.si'));
    });

    test('is a bare host, not a URL', () {
      // It is interpolated into 'https://$meetingDomain/external_api.js'
      // and into the room address. A scheme or a trailing slash here
      // produces a URL with two of them and a script that never loads.
      expect(meetingDomain, isNot(contains('/')));
      expect(meetingDomain, isNot(contains(':')));
      expect(meetingDomain, matches(RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$')));
    });

    test('can be moved without a code change', () {
      // A school that cares where its pupils are filmed points this at
      // its own deployment. The flag is read at build time, so what is
      // checkable here is that the default is only a default.
      const overridden = String.fromEnvironment(
        'JITSI_DOMAIN',
        defaultValue: 'unset',
      );
      expect(overridden, anyOf('unset', meetingDomain));
    });
  });
}
