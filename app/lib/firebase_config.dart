import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase project settings for the real backend, supplied at build time.
///
/// The usual way to do this is `flutterfire configure`, which writes a
/// generated `firebase_options.dart` full of literals. That file is
/// per-project, so a repository that imports it does not compile until
/// someone has run the tool -- which would break the demo build, the
/// tests and CI for everyone who only ever wanted to click through the
/// portals.
///
/// So the values arrive as --dart-define instead. The file always
/// compiles, demo mode never touches any of it, and the keys stay out of
/// version control:
///
///     flutter build apk --release \
///       --dart-define=DEMO_MODE=false \
///       --dart-define=FIREBASE_API_KEY=... \
///       --dart-define=FIREBASE_APP_ID=... \
///       --dart-define=FIREBASE_PROJECT_ID=... \
///       --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///       --dart-define=FIREBASE_STORAGE_BUCKET=... \
///       --dart-define=FIREBASE_AUTH_DOMAIN=...        # web only
///
/// These are client identifiers, not secrets -- they ship inside every
/// build and Firebase expects them to be public. What protects the data
/// is firestore.rules and the callable functions' own checks, never the
/// obscurity of these strings.
///
/// If you would rather use the generated file, run `flutterfire
/// configure`, import it in main.dart and pass
/// `DefaultFirebaseOptions.currentPlatform` instead. Nothing else in the
/// app depends on this class.
class FirebaseConfig {
  FirebaseConfig._();

  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// Web sign-in needs this; the mobile SDKs derive it themselves.
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  /// Everything the SDK cannot start without.
  static const _required = {
    'FIREBASE_API_KEY': apiKey,
    'FIREBASE_APP_ID': appId,
    'FIREBASE_PROJECT_ID': projectId,
    'FIREBASE_MESSAGING_SENDER_ID': messagingSenderId,
  };

  static List<String> get missing =>
      [for (final e in _required.entries) if (e.value.isEmpty) e.key];

  static bool get isConfigured => missing.isEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: messagingSenderId,
        // Empty strings would be taken as real values by the SDK, so the
        // optional ones are omitted rather than passed blank.
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
        authDomain: kIsWeb && authDomain.isNotEmpty ? authDomain : null,
      );
}
