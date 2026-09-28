import 'package:flutter/material.dart';

/// Light, dark, or whatever the device is set to.
///
/// Three rather than two, and the third is the default. A phone that
/// turns dark at sunset should take the app with it, and a school
/// laptop set to light should not be overridden by a choice somebody
/// made on their phone. "Follow the device" is the only setting that is
/// right without anybody choosing it.
///
/// The choice belongs to an account, not to the app: a shared front
/// desk computer has a morning receptionist and an afternoon one, and
/// one of them preferring dark is not a decision about the other.
enum ThemeChoice {
  system('Automatic', 'Follows your device', Icons.brightness_auto_outlined),
  light('Light', 'Always light', Icons.light_mode_outlined),
  dark('Dark', 'Always dark', Icons.dark_mode_outlined);

  final String label;
  final String meaning;
  final IconData icon;

  const ThemeChoice(this.label, this.meaning, this.icon);

  ThemeMode get mode => switch (this) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      };
}

/// Reads back what was stored, and takes anything else as the default.
///
/// Anything else includes a value written by a newer build that had a
/// fourth option. A setting nobody recognises is a setting to ignore,
/// not a reason to refuse to start.
ThemeChoice readThemeChoice(String? stored) {
  for (final choice in ThemeChoice.values) {
    if (choice.name == stored) return choice;
  }
  return ThemeChoice.system;
}

/// Where one account's choice is kept on this device.
///
/// Per account, so two people sharing a computer do not fight over it.
/// Signed out has its own slot rather than none: somebody reading the
/// sign-in page at night should be able to turn the lights down too.
String themeKeyFor(String? uid) => uid == null || uid.isEmpty
    ? 'logicclass.theme.signed-out'
    : 'logicclass.theme.user.$uid';

/// The device's most recent choice, whoever made it.
///
/// Used for the very first frame, before anybody is known. Without it
/// a person who chose dark sees the app open white and then go dark,
/// which reads as a bug rather than as a preference being applied.
const lastThemeKey = 'logicclass.theme.last';
