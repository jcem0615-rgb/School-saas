import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';

/// One slash, and the failure it causes looks like a network problem.
///
/// A hosted tenant puts every room beneath its AppID: the conference is
/// `<tenant>/<room>`. Send the bare name and nothing refuses it -- a
/// conference is created at the wrong path, the teacher sits in it
/// alone, and every student sits in a different empty one.
void main() {
  group('how a deployment addresses a room', () {
    test('is the room itself when there is no tenant', () {
      // Self-hosted and public instances. This is the default, and it
      // is what every build has shipped so far.
      expect(meetingTenant, isEmpty);
      expect(meetingRoomPath('lc-abcdefghijklmnopqrst'),
          'lc-abcdefghijklmnopqrst');
    });

    test('the room is never empty, whatever the tenant', () {
      // Guards the interpolation rather than the value: an empty room
      // would address the tenant's lobby instead of a lesson.
      expect(meetingRoomPath('lc-a'), isNotEmpty);
      expect(meetingRoomPath('lc-a'), endsWith('lc-a'));
    });

    test('the address is what the URL is built from', () {
      // The iframe and the URL must agree. They were built separately
      // and only one of them knew about the tenant at first.
      final url = meetingUrl(room: 'lc-a', domain: '8x8.vc');
      expect(url, contains('/${meetingRoomPath('lc-a')}'));
    });
  });
}
