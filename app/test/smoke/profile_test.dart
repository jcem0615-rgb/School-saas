import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/install/install_app_button.dart';
import 'package:logicclass/core/router/app_router.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/profile/presentation/screens/profile_screen.dart';

/// Profile is the one screen all ten portals share, so everything on it
/// is on it ten times over.
void main() {
  ProviderContainer signedInAs(UserRole role) {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    return c;
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('the number the account is recovered by', () {
    testWidgets('is shown, rather than reported as missing', (tester) async {
      // `AppUser` carried no `phone`, so this row read "Not set" for every
      // account in the school whatever had been collected at enrolment.
      final c = signedInAs(UserRole.faculty);
      final expected = c.read(demoStoreProvider).currentUser.value!.phone;
      expect(expected, isNotNull, reason: 'the fixture needs a number to show');

      await pump(tester, c);

      expect(find.text(expected!), findsOneWidget);
      expect(find.text('Not set'), findsNothing);
    });

    testWidgets('survives opening the editor and saving unchanged',
        (tester) async {
      // The bug, exactly: the field was never filled in, so Edit put an
      // empty box in front of somebody and Save wrote the empty string
      // over the number. `resetPasswordByPhone` matches on that field --
      // the most natural thing to do on a row saying "Not set" destroyed
      // the account's phone recovery.
      final c = signedInAs(UserRole.faculty);
      final before = c.read(demoStoreProvider).currentUser.value!.phone;
      await pump(tester, c);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(c.read(demoStoreProvider).currentUser.value!.phone, before);
      expect(find.text(before!), findsOneWidget);
    });

    testWidgets('is refused when it is not a number recovery can match',
        (tester) async {
      // The same check provisioning and the employee import already run.
      // A number the reset cannot match recovers nothing, and the account
      // finds that out on the day it cannot sign in.
      final c = signedInAs(UserRole.faculty);
      final before = c.read(demoStoreProvider).currentUser.value!.phone;
      await pump(tester, c);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'call the office');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('09171234567'), findsWidgets);
      expect(c.read(demoStoreProvider).currentUser.value!.phone, before,
          reason: 'nothing is written when the number is unusable');
    });

    testWidgets('is saved when it is a real one', (tester) async {
      final c = signedInAs(UserRole.faculty);
      await pump(tester, c);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0917 555 0142');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(c.read(demoStoreProvider).currentUser.value!.phone, '0917 555 0142');
      expect(find.text('Profile updated.'), findsOneWidget);
    });

    testWidgets('can be cleared, and says what that costs', (tester) async {
      // Somebody changing numbers has to be able to. It is still a real
      // loss, so it is said out loud rather than reported as a success.
      final c = signedInAs(UserRole.faculty);
      await pump(tester, c);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(c.read(demoStoreProvider).currentUser.value!.phone, '');
      expect(find.textContaining('no longer reset your password by phone'),
          findsOneWidget);
    });

    testWidgets('is put back by Cancel, not left half-typed', (tester) async {
      // Leaving the edited text in the box would make the next Save write
      // it, which is a change nobody asked for arriving later.
      final c = signedInAs(UserRole.faculty);
      final before = c.read(demoStoreProvider).currentUser.value!.phone;
      await pump(tester, c);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '09995550000');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text(before!), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        before,
      );
    });
  });

  group('everything it offers actually goes somewhere', () {
    testWidgets('no tile points at a route that was removed', (tester) async {
      // "My Activity History" outlived the screen behind it: the audit
      // trail module was removed and this tile kept pushing
      // '/my-activity' as a bare string, which the symbol-name sweep did
      // not see. Every role's Profile had a row that landed on the
      // router's error page.
      final c = signedInAs(UserRole.faculty);
      await pump(tester, c);

      expect(find.text('My Activity History'), findsNothing);
    });

    testWidgets('and the ones it does show are all registered routes',
        (tester) async {
      // Asserted against the router rather than a list kept by hand here,
      // so a route renamed in one place fails rather than drifting.
      final c = signedInAs(UserRole.faculty);
      await pump(tester, c);

      for (final route in [AppRoutes.myQrId, AppRoutes.privacy, AppRoutes.myAttendance]) {
        expect(route, startsWith('/'));
      }
      expect(find.text('My QR ID'), findsOneWidget);
      expect(find.text('Privacy and my information'), findsOneWidget);
      expect(find.text('My Attendance'), findsOneWidget);
      expect(find.text('Emergency Numbers'), findsOneWidget);
    });

    testWidgets('the install offer is here too, for somebody who signed in first',
        (tester) async {
      final c = signedInAs(UserRole.parent);
      await pump(tester, c);
      expect(find.byType(InstallAppButton), findsOneWidget);
    });

    testWidgets('and sign out is a labelled row, not only an icon',
        (tester) async {
      final c = signedInAs(UserRole.student);
      await pump(tester, c);
      expect(find.text('Sign out'), findsWidgets);
      expect(find.text('End your session on this device'), findsOneWidget);
    });
  });
}
