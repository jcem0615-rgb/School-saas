import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'demo/demo_overrides.dart';
import 'demo/demo_switcher.dart';
import 'features/payments/presentation/widgets/payment_submission_alerts.dart';

/// Entry point.
///
/// The app runs in one of two modes, selected at build time:
///
///   flutter run --dart-define=DEMO_MODE=true    (default)
///       Repositories are backed by an in-memory store (lib/demo/). No
///       Firebase project, emulator, or network is involved -- this is the
///       mode to use to click through the portals.
///
///   flutter run --dart-define=DEMO_MODE=false
///       The real Firestore-backed repositories. Requires a generated
///       `firebase_options.dart` and the platform config files, plus the
///       Firebase.initializeApp call restored below.
///
/// Demo mode is the default because the alternative -- launching and
/// immediately crashing on a missing firebase_options.dart -- is a worse
/// first run for anyone opening this repo.
const kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kDemoMode) {
    // Real-backend startup goes here once firebase_options.dart exists:
    //
    //   await Firebase.initializeApp(
    //     options: DefaultFirebaseOptions.currentPlatform,
    //   );
    //
    // Left as a comment rather than an import so the project builds and
    // runs without the generated config file present.
    throw UnsupportedError(
      'DEMO_MODE=false requires firebase_options.dart (flutterfire configure) '
      'and the Firebase.initializeApp call in main.dart to be uncommented.',
    );
  }

  runApp(
    ProviderScope(
      overrides: kDemoMode ? demoOverrides() : const <Override>[],
      child: const SchoolSaasApp(),
    ),
  );
}

class SchoolSaasApp extends ConsumerWidget {
  const SchoolSaasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'School Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(goRouterProvider),
      // Both of these are layered here -- above the router, inside
      // MaterialApp -- so they apply across every route.
      builder: (context, child) {
        // Tells the cashier about incoming online payments wherever they
        // are in the app. Not demo-only: this is a real feature.
        final content = PaymentSubmissionAlerts(
          child: child ?? const SizedBox.shrink(),
        );
        return kDemoMode ? DemoSwitcher(child: content) : content;
      },
    );
  }
}
