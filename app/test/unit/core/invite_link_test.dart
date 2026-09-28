import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/invite_link.dart';

/// The link a teacher pastes into a class chat.
///
/// The whole of this file is about what the link does *not* carry. A
/// link sent to a class gets forwarded, screenshotted and posted, and
/// any design where holding it is enough to be in the lesson is a
/// design where one forwarded message puts a stranger in a room of
/// children.
void main() {
  final base = Uri.parse('https://logicclass.vercel.app/');

  group('building one', () {
    final link = inviteLink(
      base: base,
      schoolId: 'school-1',
      sessionId: '2026-09-28_block-7',
    );

    test('points at the lesson, on the school\'s own site', () {
      expect(link.host, 'logicclass.vercel.app');
      expect(link.path, '/join');
      expect(link.queryParameters['school'], 'school-1');
      expect(link.queryParameters['class'], '2026-09-28_block-7');
    });

    test('carries no room name and no passcode', () {
      // The room name is what the media server actually accepts, and
      // the passcode is the second lock. Neither belongs in something
      // built to be forwarded.
      final text = link.toString().toLowerCase();

      expect(text, isNot(contains('lc-')));
      expect(text, isNot(contains('pass')));
      expect(text, isNot(contains('code')));
      expect(text, isNot(contains('token')));
      expect(link.queryParameters.keys.toSet(), {'school', 'class'});
    });

    test('drops whatever the page it was copied from was carrying', () {
      final fromDeepInside = inviteLink(
        base: Uri.parse(
          'https://logicclass.vercel.app/faculty/classes?tab=2#/roll/123',
        ),
        schoolId: 'school-1',
        sessionId: 'session-9',
      );

      expect(fromDeepInside.path, '/join');
      expect(fromDeepInside.queryParameters.containsKey('tab'), isFalse);
      expect(fromDeepInside.fragment, isEmpty);
    });

    test('goes wherever the app is served from', () {
      // A school on its own domain sends links to its own domain. One
      // hard-coded hostname here would send every school's pupils to
      // the demo.
      final own = inviteLink(
        base: Uri.parse('https://portal.sanlorenzo.edu.ph/'),
        schoolId: 's',
        sessionId: 'c',
      );

      expect(own.host, 'portal.sanlorenzo.edu.ph');
    });
  });

  group('reading one', () {
    test('finds the lesson it names', () {
      final invite = readInviteLink(
        Uri.parse('https://x.test/join?school=school-1&class=session-9'),
      );

      expect(invite, const MeetingInvite(schoolId: 'school-1', sessionId: 'session-9'));
    });

    test('survives a round trip', () {
      const invite = MeetingInvite(schoolId: 'school-1', sessionId: 'sess-2');

      expect(
        readInviteLink(inviteLink(
          base: base,
          schoolId: invite.schoolId,
          sessionId: invite.sessionId,
        )),
        invite,
      );
    });

    test('is nothing at all for a link that is not one', () {
      // This runs on whatever a browser was pointed at, including a
      // half-copied link from a chat app that truncated it. The right
      // answer is the ordinary sign-in screen, not a crash.
      for (final address in [
        'https://x.test/',
        'https://x.test/faculty',
        'https://x.test/join',
        'https://x.test/join?school=school-1',
        'https://x.test/join?class=session-9',
        'https://x.test/join?school=&class=',
        'https://x.test/join?school=%20&class=%20',
      ]) {
        expect(readInviteLink(Uri.parse(address)), isNull, reason: address);
      }
    });

    test('refuses a link that names something that is not an id', () {
      // A link is the one place a stranger chooses what this app looks
      // up. What it may name is bounded before it reaches a query.
      for (final nasty in [
        'https://x.test/join?school=../../admin&class=c',
        'https://x.test/join?school=s&class=a/b/c',
        'https://x.test/join?school=s&class=${'x' * 200}',
        'https://x.test/join?school=s%20t&class=c',
      ]) {
        expect(readInviteLink(Uri.parse(nasty)), isNull, reason: nasty);
      }
    });
  });

  group('the message around it', () {
    test('names the lesson so a parent knows what was sent', () {
      final message = inviteMessage(
        subject: 'Physics',
        section: 'Grade 10 - Rizal',
        link: inviteLink(base: base, schoolId: 's', sessionId: 'c'),
      );

      expect(message, contains('Physics'));
      expect(message, contains('Grade 10 - Rizal'));
      expect(message, contains('/join'));
    });

    test('never sweeps the code in with the link', () {
      // Together in one message they are a single thing to forward, and
      // the passcode stops being a second lock at all.
      final message = inviteMessage(
        subject: 'Physics',
        section: 'Grade 10 - Rizal',
        link: inviteLink(base: base, schoolId: 's', sessionId: 'c'),
      );

      expect(message, contains('read it out'));
      expect(message, isNot(matches(RegExp(r'[A-Z0-9]{4}-[A-Z0-9]{4}'))));
    });
  });
}
