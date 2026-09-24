import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';

/// The address a class arrives at when the lesson cannot run inside the
/// app. It is the difference between the lesson happening somewhere
/// else and the lesson not happening, so it is worth arriving properly.
void main() {
  group('the address of a lesson', () {
    test('puts the room in the path, on the configured deployment', () {
      final url = meetingUrl(room: 'lc-abcdefghijklmnopqrst', domain: 'meet.example.ph');
      expect(url, startsWith('https://meet.example.ph/lc-abcdefghijklmnopqrst'));
    });

    test('does not stop to ask a child their name', () {
      // The browser hand-off passed the room and nothing else, so a
      // class landed on a prejoin screen typing their names in -- in a
      // lesson whose whole point is a register matching names to faces.
      final url = meetingUrl(room: 'lc-a', displayName: 'Ana Cruz');
      expect(url, contains('config.prejoinPageEnabled=false'));
      expect(url, contains('config.prejoinConfig.enabled=false'));
      expect(url, contains('userInfo.displayName='));
    });

    test('survives a name with a space in it', () {
      // Which is most Filipino names. The phone build pasted the name
      // straight into the fragment and produced a URL with spaces.
      final url = meetingUrl(room: 'lc-a', displayName: 'Maria Dela Cruz');
      expect(url, isNot(contains(' ')));
      expect(Uri.parse(url).toString(), url);
      expect(Uri.decodeComponent(url.split('userInfo.displayName=').last),
          '"Maria Dela Cruz"');
    });

    test('does not let a quote in a name break out of the value', () {
      // Jitsi parses these as JSON. An unescaped quote ends the string
      // early and whatever follows is read as configuration.
      final url = meetingUrl(room: 'lc-a', displayName: 'Ana "Anya" Cruz');
      final value =
          Uri.decodeComponent(url.split('userInfo.displayName=').last);
      expect(value, r'"Ana \"Anya\" Cruz"');
    });

    test('drops control characters rather than carrying them', () {
      final url = meetingUrl(room: 'lc-a', displayName: 'Ana\nCruz');
      final value =
          Uri.decodeComponent(url.split('userInfo.displayName=').last);
      expect(value, '"AnaCruz"');
    });

    test('arrives muted when told to, and not otherwise', () {
      // Forty microphones opening at once is how an online lesson
      // starts badly. The teacher is the exception.
      expect(meetingUrl(room: 'lc-a', muted: true),
          contains('config.startWithAudioMuted=true'));
      expect(meetingUrl(room: 'lc-a'),
          isNot(contains('startWithAudioMuted')));
    });

    test('carries the token in the query, not the fragment', () {
      // Jitsi reads `jwt` from the query string. In the fragment it
      // never reaches the server and the person is asked to sign in.
      final url = meetingUrl(room: 'lc-a', token: 'head.body.sig');
      final uri = Uri.parse(url);
      expect(uri.queryParameters['jwt'], 'head.body.sig');
      expect(uri.fragment, isNot(contains('jwt')));
    });

    test('has no query at all when there is no token', () {
      expect(Uri.parse(meetingUrl(room: 'lc-a')).hasQuery, isFalse);
    });

    test('is a URL a browser will accept', () {
      final url = meetingUrl(
        room: 'lc-abcdefghijklmnopqrst',
        displayName: 'Ñoño Dela Cruz-Reyes',
        muted: true,
        token: 'head.body.sig',
      );
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.toString(), url);
    });
  });
}
