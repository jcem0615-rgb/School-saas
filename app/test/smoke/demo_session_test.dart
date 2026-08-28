import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logicclass/core/router/app_router.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_session.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart';

/// A reload used to drop a visitor back at the login screen mid-demo,
/// because demo mode keeps the session in memory and nothing wrote it
/// down. Real mode never had the problem — firebase_auth persists its
/// own — so this is the demo's stand-in for that.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DemoSession', () {
    test('remembers a signed-in account and gives it back', () async {
      final maria = DemoStore.demoAccounts.firstWhere((a) => a.email == 'faculty@demo.ph');
      await DemoSession.remember(maria);

      final restored = await DemoSession.restore();
      expect(restored?.uid, maria.uid);
    });

    test('nothing remembered restores nobody', () async {
      expect(await DemoSession.restore(), isNull);
    });

    test('signing out forgets', () async {
      await DemoSession.remember(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'admin@demo.ph'));
      await DemoSession.remember(null);

      expect(await DemoSession.restore(), isNull);
    });

    test('an account that no longer exists restores nobody', () async {
      // An older build's demo user, or a renamed one. Half a valid
      // session is worse than none.
      SharedPreferences.setMockInitialValues(
          {'logicclass.demo.signed-in-as': 'someone@who-left.ph'});
      expect(await DemoSession.restore(), isNull);
    });

    test('only the email is written — never a password, never the data', () async {
      final user = DemoStore.demoAccounts.firstWhere((a) => a.email == 'student@demo.ph');
      await DemoSession.remember(user);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'logicclass.demo.signed-in-as'});
      expect(prefs.getString('logicclass.demo.signed-in-as'), 'student@demo.ph');
    });
  });

  group('a restored session', () {
    test('seeds the store synchronously, so there is no signed-out frame', () {
      final registrar =
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph');
      final container = ProviderContainer(overrides: demoOverrides(signedInAs: registrar));
      addTearDown(container.dispose);

      // Read immediately, with nothing awaited in between: this is what
      // the first frame sees.
      expect(container.read(demoStoreProvider).currentUser.valueOrNull?.uid, registrar.uid);
    });

    test('no restored session still starts signed out', () {
      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      expect(container.read(demoStoreProvider).currentUser.valueOrNull, isNull);
    });

    testWidgets('lands on the portal, not the login screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final registrar =
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph');
      final container = ProviderContainer(overrides: demoOverrides(signedInAs: registrar));
      addTearDown(container.dispose);
      // This test is about the restored session not flashing the login
      // screen. The privacy gate is a separate redirect with its own
      // test in demo_app_boot_test.
      container.read(demoStoreProvider).acknowledgedPrivacy.add({registrar.uid});
      container.read(demoAuthRepositoryProvider).signInAs(registrar);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: container.read(goRouterProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(authStateProvider).valueOrNull?.uid, registrar.uid);
      expect(find.text('Sign in'), findsNothing,
          reason: 'a remembered session must not show the login form again');
      expect(find.text('Student Records'), findsWidgets,
          reason: "the registrar's own portal");
    });
  });

  group('the demo repositories', () {
    test('logging in is remembered, logging out is forgotten', () async {
      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      final auth = container.read(demoAuthRepositoryProvider);

      await auth.login(email: 'director@demo.ph', password: DemoStore.password);
      // remember() is deliberately not awaited by login(), so give the
      // write a turn to land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await DemoSession.restore())?.email, 'director@demo.ph');

      await auth.logout();
      expect(await DemoSession.restore(), isNull);
    });

    test('the role switcher is remembered too', () async {
      // Otherwise a reload comes back as whoever typed a password rather
      // than the role you were actually looking at.
      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);

      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == 'guidance@demo.ph'),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await DemoSession.restore())?.email, 'guidance@demo.ph');
    });

    test('a failed login is not remembered', () async {
      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);

      await container
          .read(demoAuthRepositoryProvider)
          .login(email: 'director@demo.ph', password: 'wrong');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await DemoSession.restore(), isNull);
    });
  });
}
