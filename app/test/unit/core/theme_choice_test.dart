import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/theme/theme_choice.dart';
import 'package:logicclass/core/theme/theme_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or whatever the device is set to.
///
/// The choice belongs to an account rather than to the app, because a
/// school's front desk computer has a morning receptionist and an
/// afternoon one, and one of them preferring dark is not a decision
/// about the other.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemePreference.useForTesting(null);
  });

  tearDown(() => ThemePreference.useForTesting(null));

  Future<void> openStore() => ThemePreference.warmUp();

  group('the three choices', () {
    test('each mean something to Flutter', () {
      expect(ThemeChoice.system.mode, ThemeMode.system);
      expect(ThemeChoice.light.mode, ThemeMode.light);
      expect(ThemeChoice.dark.mode, ThemeMode.dark);
    });

    test('each say what they are, in words and a symbol', () {
      for (final choice in ThemeChoice.values) {
        expect(choice.label, isNotEmpty);
        expect(choice.meaning, isNotEmpty);
      }
    });

    test('are read back by name', () {
      for (final choice in ThemeChoice.values) {
        expect(readThemeChoice(choice.name), choice);
      }
    });

    test('fall back to following the device for anything else', () {
      // Including a value written by a newer build that had a fourth
      // option. A setting nobody recognises is a setting to ignore, not
      // a reason to refuse to start.
      for (final stored in [null, '', 'sepia', 'DARK', 'true', '2']) {
        expect(readThemeChoice(stored), ThemeChoice.system, reason: '$stored');
      }
    });
  });

  group('where it is kept', () {
    test('is a different slot for every account', () {
      expect(themeKeyFor('user_a'), isNot(themeKeyFor('user_b')));
      expect(themeKeyFor('user_a'), contains('user_a'));
    });

    test('and one for nobody, which is not any account\'s', () {
      expect(themeKeyFor(null), isNot(themeKeyFor('user_a')));
      expect(themeKeyFor(''), themeKeyFor(null));
    });
  });

  group('remembering it', () {
    test('gives each account its own', () async {
      await openStore();

      await ThemePreference.write('user_a', ThemeChoice.dark);
      await ThemePreference.write('user_b', ThemeChoice.light);

      expect(ThemePreference.read('user_a'), ThemeChoice.dark);
      expect(ThemePreference.read('user_b'), ThemeChoice.light);
    });

    test('does not hand a new account the last person\'s preference',
        () async {
      // The afternoon receptionist signs in and gets the app as the
      // school set it up, not as the morning one likes it.
      await openStore();
      await ThemePreference.write('user_a', ThemeChoice.dark);

      expect(ThemePreference.read('user_b'), ThemeChoice.system);
    });

    test('does lend it to the first frame, before anybody is known',
        () async {
      // Otherwise a person who chose dark watches the app open white
      // and then change its mind in front of them.
      await openStore();
      await ThemePreference.write('user_a', ThemeChoice.dark);

      expect(ThemePreference.read(null), ThemeChoice.dark);
    });

    test('and prefers what was chosen while signed out, when there is one',
        () async {
      await openStore();
      await ThemePreference.write('user_a', ThemeChoice.dark);
      await ThemePreference.write(null, ThemeChoice.light);

      expect(ThemePreference.read(null), ThemeChoice.light);
      expect(ThemePreference.read('user_a'), ThemeChoice.dark);
    });

    test('survives being written twice', () async {
      await openStore();

      await ThemePreference.write('user_a', ThemeChoice.dark);
      await ThemePreference.write('user_a', ThemeChoice.light);

      expect(ThemePreference.read('user_a'), ThemeChoice.light);
    });
  });

  group('when the device will not remember anything', () {
    test('reading still answers, rather than throwing', () {
      // A private window, a locked-down browser, a full disk. It must
      // cost somebody a theme that resets, never an app that will not
      // open.
      expect(ThemePreference.read('user_a'), ThemeChoice.system);
      expect(ThemePreference.read(null), ThemeChoice.system);
    });

    test('and writing is a no-op rather than a crash', () async {
      await expectLater(
        ThemePreference.write('user_a', ThemeChoice.dark),
        completes,
      );
      expect(ThemePreference.read('user_a'), ThemeChoice.system);
    });
  });
}
