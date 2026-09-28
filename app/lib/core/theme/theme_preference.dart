import 'package:shared_preferences/shared_preferences.dart';

import 'theme_choice.dart';

/// Where each account's light-or-dark choice is kept.
///
/// Read synchronously, deliberately. The theme is needed by the very
/// first frame, and a preference that arrives a frame late is a person
/// who chose dark watching the app open white and then change its mind
/// in front of them. So the store is opened once before `runApp` -- the
/// same thing the demo session already does, and for the same reason --
/// and every read after that is off the copy in memory.
///
/// Every method swallows storage failures. A private window, a
/// locked-down browser or a full disk must cost somebody a theme that
/// resets, never an app that will not open.
class ThemePreference {
  ThemePreference._();

  static SharedPreferences? _store;

  /// Opens the store. Called once, before the first frame.
  static Future<void> warmUp() async {
    try {
      _store = await SharedPreferences.getInstance();
    } catch (_) {
      // Nothing is remembered this run. Everything below copes.
    }
  }

  /// Replaces the store. For tests, which cannot open a real one.
  static void useForTesting(SharedPreferences? store) => _store = store;

  /// This account's choice, or the device's last one, or automatic.
  ///
  /// The fallback chain is what makes the first frame right. Before
  /// anybody has signed in there is no account to ask, but there is
  /// usually a choice somebody made on this device last time -- and on
  /// a personal phone that is the same person.
  static ThemeChoice read(String? uid) {
    final store = _store;
    if (store == null) return ThemeChoice.system;
    try {
      final mine = store.getString(themeKeyFor(uid));
      if (mine != null) return readThemeChoice(mine);
      // Only for the signed-out slot. A signed-in account that has
      // never chosen follows the device rather than inheriting whatever
      // the last person at this computer preferred.
      if (uid == null || uid.isEmpty) {
        return readThemeChoice(store.getString(lastThemeKey));
      }
      return ThemeChoice.system;
    } catch (_) {
      return ThemeChoice.system;
    }
  }

  /// Remembers [choice] for this account, and for this device.
  static Future<void> write(String? uid, ThemeChoice choice) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.setString(themeKeyFor(uid), choice.name);
      await store.setString(lastThemeKey, choice.name);
    } catch (_) {
      // The setting applies for this session and is forgotten after it.
    }
  }
}
