import 'dart:math';

/// A room name for a demo lesson, in the shape the server generates.
///
/// The same shape matters more than it sounds. Two other things check
/// rooms against the real format -- `isMeetingRoom` on the server, and
/// the demo's own token endpoint -- and a demo that generates a
/// different shape is refused by both. That is not a cosmetic
/// divergence: it is the demo failing to hold a class and reporting
/// that live video is not switched on.
///
/// 24 characters of lower-case alphanumeric, which is what 15 random
/// bytes of base64 comes to once the punctuation is dropped. Far past
/// guessing, and short enough to read out over a bad phone line to a
/// parent whose child cannot get in.
///
/// `Random.secure()` rather than the default: the room name is the whole
/// of what keeps somebody out of a lesson, and a predictable sequence is
/// not a secret. The demo is shown to schools, and a demo that teaches
/// "the room name is a counter" teaches the wrong thing.
String newDemoMeetingRoom() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final name = StringBuffer('lc-');
  for (var i = 0; i < 24; i++) {
    name.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return name.toString();
}
