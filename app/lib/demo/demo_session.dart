import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/domain/entities/app_user.dart';
import 'demo_store.dart';

/// Remembers which demo account was signed in, across a reload.
///
/// Demo mode keeps everything in memory, which meant a browser refresh —
/// or the F5 somebody hits out of habit — dropped them back at the login
/// screen mid-demo. Real mode never had this problem: firebase_auth
/// persists its own session, so this is the demo's stand-in for that and
/// nothing else in the app uses it.
///
/// Only the *email* is stored, never a password and never any of the
/// demo's data. The account is looked back up in [DemoStore.demoAccounts]
/// on the way in, so a stored value that no longer matches an account —
/// an old build, a renamed demo user — restores nobody rather than
/// resurrecting a half-valid session.
class DemoSession {
  DemoSession._();

  static const _key = 'logicclass.demo.signed-in-as';

  /// Reads the remembered account. Returns null if there is none, if it
  /// no longer exists, or if storage is unavailable — a demo that cannot
  /// remember a session must still open.
  static Future<AppUser?> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_key);
      if (email == null || email.isEmpty) return null;
      return DemoStore.demoAccounts
          .where((a) => a.email.toLowerCase() == email.toLowerCase())
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Remembers [user], or forgets whoever was remembered when null.
  ///
  /// Deliberately not awaited by its callers: signing in must not wait on
  /// a disk write, and a failed write costs a re-login rather than
  /// anything a demo visitor would notice.
  static Future<void> remember(AppUser? user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, user.email);
      }
    } catch (_) {
      // Storage disabled (a private window, a locked-down browser). The
      // demo still works; it just forgets.
    }
  }
}
