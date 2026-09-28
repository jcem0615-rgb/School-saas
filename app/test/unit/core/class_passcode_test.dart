import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/class_passcode.dart';

/// The code a teacher reads out, and the rule that actually judges it.
///
/// The demo mints its own codes because it has no Cloud Functions, so
/// there are two implementations of one format in two languages. That
/// is exactly the arrangement that broke the room name and cost an
/// afternoon: the demo generated a shape the endpoint refused, and
/// every request came back as "live video is not switched on".
///
/// So this reads the alphabet and the length out of the TypeScript and
/// holds the Dart to them. Change either side and this fails, which is
/// the point.
void main() {
  String serverSource() =>
      File('../functions/src/shared/meeting/passcode.ts').readAsStringSync();

  group('the two implementations agree', () {
    test('about the alphabet', () {
      final declared = RegExp('const ALPHABET = "([^"]+)"')
          .firstMatch(serverSource())
          ?.group(1);

      expect(declared, isNotNull,
          reason: 'the server no longer declares ALPHABET the way this reads it');
      expect(passcodeAlphabet, declared);
    });

    test('about the length', () {
      final declared = RegExp(r'PASSCODE_LENGTH = (\d+)')
          .firstMatch(serverSource())
          ?.group(1);

      expect(declared, isNotNull);
      expect(passcodeLength, int.parse(declared!));
    });

    test('about which characters are left out and why', () {
      // I and L for one, O for zero, U so that eight random characters
      // cannot spell something a teacher has to read to a class.
      for (final excluded in ['I', 'L', 'O', 'U']) {
        expect(passcodeAlphabet, isNot(contains(excluded)));
      }
    });
  });

  group('making one', () {
    test('is eight characters, and a different eight each time', () {
      final codes = {for (var i = 0; i < 500; i++) newClassPasscode()};

      expect(codes.length, 500);
      expect(codes.every((c) => c.length == passcodeLength), isTrue);
    });

    test('is recognised by the checker that guards the door', () {
      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        final code = newClassPasscode(random);
        expect(isClassPasscode(code), isTrue);
        expect(normaliseClassPasscode(displayClassPasscode(code)), code);
      }
    });
  });

  group('reading one back', () {
    test('forgives the dash it was shown with, and the shift key', () {
      expect(normaliseClassPasscode('a1b2-c3d4'), 'A1B2C3D4');
      expect(normaliseClassPasscode('  A1B2 C3D4 '), 'A1B2C3D4');
      expect(displayClassPasscode('A1B2C3D4'), 'A1B2-C3D4');
    });

    test('takes an eye for a one and an oh for a zero', () {
      // A child who hears "eye" and types I is let in rather than told
      // they got it wrong.
      expect(classPasscodeMatches('IOIO2345', '10102345'), isTrue);
      expect(classPasscodeMatches('LLLL2345', '11112345'), isTrue);
    });

    test('refuses everything when the lesson has no code', () {
      // A lesson without a code must not be a lesson where the empty
      // string is the code.
      for (final stored in <String?>[null, '', '   ']) {
        expect(classPasscodeMatches('', stored), isFalse);
        expect(classPasscodeMatches('A1B2C3D4', stored), isFalse);
      }
    });

    test('is not a code when it is the wrong length or shape', () {
      expect(isClassPasscode('A1B2C3D4'), isTrue);
      expect(isClassPasscode('A1B2C3D'), isFalse);
      expect(isClassPasscode('A1B2C3D45'), isFalse);
      expect(isClassPasscode('A1B2C3DU'), isFalse);
      expect(isClassPasscode(''), isFalse);
    });
  });
}
