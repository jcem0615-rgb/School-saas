import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
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
        // Tells the cashier about incoming online payments wherever they
        // are in the app. Not demo-only: this is a real feature.
        // The wash the whole app sits on. Above the router so it is
        // painted once and every route's transparent scaffold shows it
        // through, rather than each screen carrying its own copy.
        final content = AmbientBackground(
          child: PaymentSubmissionAlerts(
            child: child ?? const SizedBox.shrink(),
          ),
        );
        return kDemoMode ? DemoSwitcher(child: content) : content;
      },
    );
  }
}
