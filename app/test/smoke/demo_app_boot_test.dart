import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logicclass/features/terms/domain/entities/terms_of_service.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/router/app_router.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/main.dart';

/// Boots the real widget tree (router, theme, all ten portals) against the
/// demo repositories.
///
/// This covers the class of failure that is effectively invisible from a
/// browser -- an exception thrown before the first frame paints, which
/// leaves a blank page and an empty console -- and it verifies the thing
/// demo mode exists to let you check: that every role actually lands on a
/// working portal.
void main() {
  testWidgets('boots to the login screen with no exception', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: demoOverrides(), child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The product name and the submit button: the two things that have to
    // be on the front door. Asserting the wordmark rather than the strap
    // line, which is copy and free to change.
    expect(find.text('LogicClass'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('every demo role lands on its own portal without throwing',
      (tester) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);

    // The privacy notice and the terms both stand in front of every
    // portal on a fresh session; each gets its own assertion below.
    // Marking these accounts as past both keeps this test about whether
    // each portal opens.
    final uids = {for (final account in DemoStore.demoAccounts) account.uid};
    container.read(demoStoreProvider).acknowledgedPrivacy.add(uids);
    container.read(demoStoreProvider).acceptedTerms.add(uids);

    for (final account in DemoStore.demoAccounts) {
      final label = account.role.displayName;
      demoSignInAs(
        container.read(demoAuthRepositoryProvider),
        container.read(goRouterProvider),
        account,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$label portal threw on open');
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.homeFor(account.role),
        reason: '$label did not land on its portal home',
      );
      expect(find.byType(Scaffold), findsWidgets, reason: '$label rendered nothing');
    }
  });

  testWidgets('a fresh sign-in is held at the privacy notice until it is read',
      (tester) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final student = DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student);
    demoSignInAs(
      container.read(demoAuthRepositoryProvider),
      container.read(goRouterProvider),
      student,
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.acknowledgePrivacy,
      reason: 'a notice somebody can navigate past is one the school cannot '
          'say was given',
    );
    expect(find.text('I have read this'), findsOneWidget);

    // The button stays dead until the notice has been scrolled through,
    // which is the point of it -- so the test has to read the page the
    // way a person would.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('I have read this'));
    await tester.pumpAndSettle();

    // Not the portal yet: the terms are the next gate, in that order. A
    // person is told what is held about them before being asked to agree
    // to anything.
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.acceptTerms,
      reason: 'acknowledging the notice should hand them to the terms',
    );
  });

  testWidgets('and then held at the terms until they accept', (tester) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final student = DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student);
    // Past the notice, so this test is about the terms alone.
    container.read(demoStoreProvider).acknowledgedPrivacy.add({student.uid});
    demoSignInAs(
      container.read(demoAuthRepositoryProvider),
      container.read(goRouterProvider),
      student,
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.acceptTerms);

    // Unlike the notice, this one offers a way out -- an agreement
    // nobody can decline is not an agreement.
    expect(find.text('I do not accept - sign out'), findsOneWidget);

    final accept = find.text('I accept these terms');
    expect(
      tester.widget<FilledButton>(find.ancestor(
        of: accept,
        matching: find.byType(FilledButton),
      )).onPressed,
      isNull,
      reason: 'live before the text has moved is a button people press '
          'without looking',
    );

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.homeFor(UserRole.student),
      reason: 'accepting should let them through to their portal',
    );
    expect(
      container.read(demoStoreProvider).currentUser.value?.termsVersion,
      TermsOfService.version,
      reason: 'the version accepted is what the school can point at later',
    );
  });

  testWidgets('shared sub-routes open without throwing', (tester) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);

    // Routes every signed-in user can reach, plus the two drill-downs that
    // take a path parameter. The dashboards are covered above; these are
    // the screens a reviewer clicks into next, and each one resolves its
    // own data from a different fake, so a broken fake shows up here.
    const asRegistrar = [
      AppRoutes.myQrId,
      AppRoutes.myAttendance,
      AppRoutes.myActivity,
      AppRoutes.profile,
      AppRoutes.notifications,
      AppRoutes.messages,
      AppRoutes.myLeave,
      AppRoutes.myTimesheet,
      AppRoutes.leaveRequests,
      AppRoutes.timesheets,
      AppRoutes.recordPayment,
      '${AppRoutes.paymentHistory}/stu_001',
    ];

    demoSignInAs(
      container.read(demoAuthRepositoryProvider),
      router,
      DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
    );
    await tester.pumpAndSettle();

    for (final route in asRegistrar) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$route threw on open');
      expect(find.byType(Scaffold), findsWidgets, reason: '$route rendered nothing');
    }

    // Owner's school drill-down lives outside the tenant routes.
    demoSignInAs(
      container.read(demoAuthRepositoryProvider),
      router,
      DemoStore.demoAccounts.firstWhere((a) => a.email == 'owner@demo.ph'),
    );
    await tester.pumpAndSettle();

    router.go('${AppRoutes.ownerHome}/schools/${DemoStore.schoolId}');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'school detail threw on open');
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('every remaining router route opens for a role that may reach it',
      (tester) async {
    // The test above walks the routes any signed-in person can reach. This
    // one walks what is left, so that between them every GoRoute in
    // app_router.dart has been opened at least once. A screen nobody ever
    // navigates to in a test is a screen whose first render is being
    // checked for the first time by whoever is holding the laptop.
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);
    final uids = {for (final account in DemoStore.demoAccounts) account.uid};
    container.read(demoStoreProvider).acknowledgedPrivacy.add(uids);
    container.read(demoStoreProvider).acceptedTerms.add(uids);

    // Director reaches the three guarded surfaces; the scanner and the
    // privacy notice are open to everybody, and are checked as the
    // registrar because that is who stands at a scanner all morning.
    const byEmail = <String, List<String>>{
      'director@demo.ph': [
        AppRoutes.auditTrail,
        AppRoutes.reports,
        AppRoutes.systemCheck,
      ],
      'registrar@demo.ph': [
        AppRoutes.scanAttendance,
        AppRoutes.privacy,
      ],
    };

    for (final entry in byEmail.entries) {
      demoSignInAs(
        container.read(demoAuthRepositoryProvider),
        router,
        DemoStore.demoAccounts.firstWhere((a) => a.email == entry.key),
      );
      await tester.pumpAndSettle();

      for (final route in entry.value) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$route threw on open');
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          route,
          reason: '$route redirected away from ${entry.key}, who should reach it',
        );
        expect(find.byType(Scaffold), findsWidgets, reason: '$route rendered nothing');
      }
    }
  });

  testWidgets('the three Director and Admin surfaces turn everybody else away',
      (tester) async {
    // The guard in app_router.dart, asserted from the outside. It is a
    // convenience rather than the security boundary -- the rules refuse
    // the underlying queries per document, which is what the rules suite
    // proves - but a role that reached one of these screens would sit in
    // front of a wall of permission errors, and conclude the app is
    // broken rather than that they were somewhere they should not be.
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final router = container.read(goRouterProvider);
    final uids = {for (final account in DemoStore.demoAccounts) account.uid};
    container.read(demoStoreProvider).acknowledgedPrivacy.add(uids);
    container.read(demoStoreProvider).acceptedTerms.add(uids);

    const guarded = [AppRoutes.auditTrail, AppRoutes.reports, AppRoutes.systemCheck];
    final turnedAway = DemoStore.demoAccounts.where(
      (a) => a.role != UserRole.director && a.role != UserRole.admin,
    );

    for (final account in turnedAway) {
      demoSignInAs(container.read(demoAuthRepositoryProvider), router, account);
      await tester.pumpAndSettle();

      for (final route in guarded) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$route threw for ${account.role.displayName}');
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.homeFor(account.role),
          reason: '${account.role.displayName} reached $route and should not have',
        );
      }
    }
  });

  testWidgets('signing out returns to the login screen', (tester) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final auth = container.read(demoAuthRepositoryProvider);
    demoSignInAs(auth, container.read(goRouterProvider), DemoStore.demoAccounts.first);
    await tester.pumpAndSettle();

    // Not awaited: logout has an artificial delay, and under the test
    // binding's fake clock a bare `await` would wait on a timer that only
    // pumping can advance.
    unawaited(auth.logout());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      container.read(goRouterProvider).routerDelegate.currentConfiguration.uri.path,
      AppRoutes.login,
    );
  });
}
