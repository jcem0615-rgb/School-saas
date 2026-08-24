import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
