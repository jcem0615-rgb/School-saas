import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file in the suite -- `flutter test` picks this
/// up by name.
///
/// It exists for one reason. DemoAuthRepository.signInAs remembers the
/// session through SharedPreferences, and does not await the write:
/// signing in must not wait on a disk write. In a test file that never
/// registered the plugin, that unawaited call fails with
/// MissingPluginException *after the test that triggered it has already
/// finished*, and the runner attributes the error to whichever test
/// happened to still be open. It reads as an unrelated test failing at
/// random, which is exactly what it did:
///
///   ❌ parent_emergency_test.dart: the provider gathers every linked child
///      MissingPluginException(No implementation found for method getAll
///      on channel plugins.flutter.io/shared_preferences)
///
/// DemoSession.remember catches its own errors, but the plugin reports
/// this one through the zone before that catch can see it, so guarding
/// the call site is not enough -- the plugin has to exist.
///
/// An in-memory store for every test file is also simply more honest:
/// signing in during a test now behaves the way it does in the app,
/// rather than throwing into the void.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
