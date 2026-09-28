/// The code a teacher reads out before a lesson starts.
///
/// The server's copy of this is `functions/src/shared/meeting/passcode.ts`,
/// and the two have to agree about the alphabet and the length or the
/// demo teaches a shape the product refuses -- which is exactly how the
/// room name broke, and cost an afternoon. There is a test that reads
/// the alphabet out of the TypeScript and holds this to it.
///
/// Generated here only for the demo, which has no Cloud Functions. In
/// the product the code is minted on the server and this file only
/// reads it back and shows it.
library;

import 'dart:math';

/// Crockford's base32: no I, no L, no O, no U.
///
/// Three of them because a code read aloud to a ten-year-old must not
/// turn on whether a character was a one or an ell; the fourth so that
/// eight random characters cannot spell something a teacher then has to
/// read out to a class.
const passcodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Eight from thirty-two: about a thousand billion codes.
const passcodeLength = 8;

/// A new code. Demo only -- see the note above.
String newClassPasscode([Random? random]) {
  final source = random ?? Random.secure();
  final code = StringBuffer();
  for (var i = 0; i < passcodeLength; i++) {
    code.write(passcodeAlphabet[source.nextInt(passcodeAlphabet.length)]);
  }
  return code.toString();
}

/// What somebody typed, as the code they meant.
///
/// Dashes and spaces go, because a code shown as `A1B2-C3D4` is typed
/// back with the dash. Case goes, because a phone capitalises the first
/// letter on its own. An eye becomes a one and an oh a zero, so a child
/// who hears "eye" and types I is let in rather than told they are
/// wrong.
String normaliseClassPasscode(String given) => given
    .toUpperCase()
    .replaceAll(RegExp('[^0-9A-Z]'), '')
    .replaceAll(RegExp('[IL]'), '1')
    .replaceAll('O', '0');

/// Whether this could be a code this app made.
bool isClassPasscode(String given) {
  final code = normaliseClassPasscode(given);
  return code.length == passcodeLength &&
      code.split('').every(passcodeAlphabet.contains);
}

/// Whether what was typed is the code that was set.
bool classPasscodeMatches(String given, String? stored) {
  if (stored == null || stored.isEmpty) return false;
  final typed = normaliseClassPasscode(given);
  final real = normaliseClassPasscode(stored);
  return real.isNotEmpty && typed == real;
}

/// How it is shown to a teacher, and how it should be read out.
String displayClassPasscode(String code) {
  final clean = normaliseClassPasscode(code);
  if (clean.length != passcodeLength) return clean;
  return '${clean.substring(0, 4)}-${clean.substring(4)}';
}
