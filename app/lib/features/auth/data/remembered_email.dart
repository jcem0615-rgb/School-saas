import 'package:shared_preferences/shared_preferences.dart';

/// The email of whoever last signed in with "Remember me" ticked.
///
/// Only the email. A password is never stored, on any platform, under any
/// setting — a school's shared front-desk computer is exactly the machine
/// where a remembered password becomes everybody's password, and there is
/// no version of this feature worth that.
///
/// What it buys is the half of sign-in that is tedious rather than
/// secret: a teacher on their own phone types a password instead of a
/// password and a long school address. Staying signed in between sessions
/// is separate and already handled — firebase_auth persists its own
/// session in real mode, and [DemoSession] does the same for the demo.
///
/// Every method swallows storage failures. A private window, a locked-down
/// browser or a full disk must cost somebody a retyped email, never a
/// sign-in screen that will not open.
class RememberedEmail {
  RememberedEmail._();

  static const _key = 'logicclass.auth.remembered-email';

  /// The remembered email, or null when there is none.
  static Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_key);
      return (email == null || email.isEmpty) ? null : email;
    } catch (_) {
      return null;
    }
  }

  /// Remembers [email], or forgets whatever was remembered when null.
  static Future<void> write(String? email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = email?.trim() ?? '';
      if (trimmed.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, trimmed);
      }
    } catch (_) {
      // Storage unavailable. The sign-in still works; it just forgets.
    }
  }
}
