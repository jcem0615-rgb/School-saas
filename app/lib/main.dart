import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/session/single_device_session.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/glass.dart';
import 'demo/demo_session.dart';
import 'demo/demo_overrides.dart';
import 'demo/demo_switcher.dart';
import 'features/payments/presentation/widgets/payment_submission_alerts.dart';
import 'firebase_config.dart';

/// Entry point.
///
/// The app runs in one of two modes, selected at build time:
///
///   flutter run --dart-define=DEMO_MODE=true    (default)
///       Repositories are backed by an in-memory store (lib/demo/). No
///       Firebase project, emulator, or network is involved -- this is the
///       mode to use to click through the portals.
///
///   flutter run --dart-define=DEMO_MODE=false \
///       --dart-define=FIREBASE_API_KEY=... (and the rest)
///       The real Firestore-backed repositories, against a live Firebase
///       project. See [FirebaseConfig] for the full list of values and
///       why they arrive as --dart-define rather than a generated file.
///
/// Demo mode is the default because the alternative -- a first run that
/// fails on a project nobody has created yet -- is a worse introduction
/// for anyone opening this repo. It is also the mode the demo builds and
/// the test suite use, and none of that changes when a real backend is
/// configured: the two modes coexist.
const kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

/// Points every SDK at a locally running Firebase Emulator Suite.
///
/// Only meaningful with DEMO_MODE=false: demo mode never starts Firebase
/// at all. This is what makes the real repositories -- and the System
/// Check that probes them -- runnable without a cloud project, against
/// the actual rules engine and the actual Functions runtime rather than
/// a stand-in for them.
///
///     flutter build web --dart-define=DEMO_MODE=false \
///       --dart-define=USE_FIREBASE_EMULATORS=true \
///       --dart-define=FIREBASE_PROJECT_ID=demo-logicclass ...
///
/// Deliberately opt-in and off by default. A build that silently talked
/// to localhost instead of the school's project would be the worst kind
/// of configuration bug: everything would appear to work, against
/// nothing.
const kUseFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

/// Where the suite is listening. The ports are the ones in firebase.json.
const kEmulatorHost =
    String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '127.0.0.1');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kDemoMode) {
    if (!FirebaseConfig.isConfigured) {
      // Naming the missing keys, rather than failing with "no Firebase
      // app", because the cause is always a forgotten --dart-define and
      // the SDK's own error says nothing about which one.
      throw StateError(
        'DEMO_MODE=false needs the Firebase project settings. '
        'Missing: ${FirebaseConfig.missing.join(', ')}. '
        'See lib/firebase_config.dart.',
      );
    }
    await Firebase.initializeApp(options: FirebaseConfig.options);
    if (kUseFirebaseEmulators) await _connectEmulators();
  }

  // Restored before runApp, not after: awaiting it here means the first
  // frame already knows who is signed in. Reading it from inside the
  // widget tree would paint the login screen and then jump to the
  // portal, which reads as being signed out and signed straight back in.
  //
  // Real mode needs no equivalent -- firebase_auth restores its own
  // session -- which is why this is inside the demo branch.
  final restored = kDemoMode ? await DemoSession.restore() : null;

  runApp(
    ProviderScope(
      overrides: kDemoMode ? demoOverrides(signedInAs: restored) : const <Override>[],
      child: const LogicClassApp(),
    ),
  );
}

/// Redirects each SDK to the emulator suite.
///
/// Called after initializeApp and before anything reads a repository,
/// because every one of these throws once its SDK has issued a request.
Future<void> _connectEmulators() async {
  FirebaseFirestore.instance.useFirestoreEmulator(kEmulatorHost, 8080);
  await FirebaseAuth.instance.useAuthEmulator(kEmulatorHost, 9099);
  await FirebaseStorage.instance.useStorageEmulator(kEmulatorHost, 9199);
  // Same region the callables deploy to, so the instance this reaches is
  // the one firebaseFunctionsProvider hands out.
  FirebaseFunctions.instanceFor(region: 'asia-southeast1')
      .useFunctionsEmulator(kEmulatorHost, 5001);
  debugPrint('Firebase SDKs pointed at the emulator suite on $kEmulatorHost.');
}

class LogicClassApp extends ConsumerWidget {
  const LogicClassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'LogicClass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(goRouterProvider),
      // Both of these are layered here -- above the router, inside
      // MaterialApp -- so they apply across every route.
      builder: (context, child) {
        // AmbientBackground: the wash the whole app sits on. Painted
        // once here so every route's transparent scaffold shows it
        // through, rather than each screen carrying its own copy.
        //
        // SingleDeviceSession: one account, one device. Signs this one
        // out when the account is signed in somewhere else, which can
        // land on any screen and so belongs above all of them.
        //
        // PaymentSubmissionAlerts: tells the cashier about incoming
        // online payments wherever they are in the app. Not demo-only;
        // this is a real feature.
        final content = AmbientBackground(
          child: SingleDeviceSession(
            child: PaymentSubmissionAlerts(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
        return kDemoMode ? DemoSwitcher(child: content) : content;
      },
    );
  }
}
