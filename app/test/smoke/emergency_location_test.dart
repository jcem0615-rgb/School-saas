import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/core/location/location_probe.dart';
import 'package:school_saas/core/location/location_providers.dart';
import 'package:school_saas/core/theme/app_theme.dart';
import 'package:school_saas/demo/demo_location_probe.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/emergency/presentation/controllers/emergency_controller.dart';
import 'package:school_saas/features/emergency/presentation/screens/emergency_alerts_screen.dart';

/// An emergency alert carries where the student was.
///
/// "Send help" is not actionable on its own -- a school is a big place and
/// a student in trouble may not be able to say where they are. The two
/// things this has to get right are that the location arrives with the
/// alert, and that a missing location never stops one.
class _NeverAnsweringProbe implements LocationProbe {
  @override
  Future<LocationResult> current({Duration timeout = const Duration(seconds: 8)}) {
    // Hangs forever, the way a plugin on a device with no signal does --
    // and, importantly, ignores the timeout it was handed. The controller
    // is expected to be the thing that gives up, not the caller.
    //
    // A Completer rather than a long Future.delayed: a delayed future
    // leaves a pending timer behind and the test framework fails teardown
    // on it, which would be the fake's problem showing up as the app's.
    return Completer<LocationResult>().future;
  }
}

void main() {
  ProviderContainer containerWith(LocationProbe probe) {
    final container = ProviderContainer(overrides: [
      ...demoOverrides(),
      locationProbeProvider.overrideWith((ref) => probe),
    ]);
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student),
        );
    return container;
  }

  Future<void> raise(WidgetTester tester, ProviderContainer container) async {
    final student = DemoStore.demoAccounts
        .firstWhere((a) => a.role == UserRole.student);
    unawaited(container.read(emergencyActionControllerProvider.notifier).raiseAlert(
          studentId: 'student-1',
          studentName: student.fullName,
          section: 'Grade 10 - Rizal',
          message: 'Sprained my ankle on the stairs',
        ));
    // Past the probe's own delay and the demo repository's latency.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the alert carries where the student was', (tester) async {
    final container = containerWith(const DemoLocationProbe());
    await raise(tester, container);

    final alert = container.read(demoStoreProvider).emergencyAlerts.value.first;
    expect(alert.hasLocation, isTrue);
    expect(alert.latitude, closeTo(14.6507, 0.0001));
    expect(alert.longitude, closeTo(121.1029, 0.0001));
    expect(alert.locationAccuracyMeters, 12);
    expect(alert.locationFailure, isNull);
  });

  testWidgets('a student who declines to share still raises the alert',
      (tester) async {
    final container = containerWith(const DecliningLocationProbe());
    await raise(tester, container);

    final alerts = container.read(demoStoreProvider).emergencyAlerts.value;
    expect(alerts, hasLength(1), reason: 'the alert is the point; the fix is a bonus');
    expect(alerts.first.hasLocation, isFalse);
    expect(alerts.first.locationFailure, LocationFailure.permissionDenied);
  });

  testWidgets('a device that never answers does not hold up the alert',
      (tester) async {
    final container = containerWith(_NeverAnsweringProbe());
    final student =
        DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student);

    unawaited(container.read(emergencyActionControllerProvider.notifier).raiseAlert(
          studentId: 'student-1',
          studentName: student.fullName,
          section: 'Grade 10 - Rizal',
        ));

    // Nothing yet: the probe is still hanging.
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(demoStoreProvider).emergencyAlerts.value, isEmpty);

    // Past the controller's own deadline, the alert goes anyway.
    await tester.pump(EmergencyActionController.locationTimeout);
    await tester.pump(const Duration(seconds: 1));

    final alerts = container.read(demoStoreProvider).emergencyAlerts.value;
    expect(alerts, hasLength(1));
    expect(alerts.first.locationFailure, LocationFailure.timeout);
  });

  testWidgets('staff see the location, and can open it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = containerWith(const DemoLocationProbe());
    await raise(tester, container);

    // Switch to somebody who reads the queue.
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
        );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light(), home: const EmergencyAlertsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('14.65070'), findsOneWidget);
    expect(find.textContaining('121.10290'), findsOneWidget);
    expect(find.textContaining('accurate to about 12 m'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
  });

  testWidgets('staff are told which kind of "no location" this is',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = containerWith(const DecliningLocationProbe());
    await raise(tester, container);

    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
        );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light(), home: const EmergencyAlertsScreen()),
    ));
    await tester.pumpAndSettle();

    // Not a blank space: staff need to know nobody has a position, rather
    // than assume one is still coming.
    expect(find.text('The student did not share their location.'), findsOneWidget);
    expect(find.text('Open in Maps'), findsNothing);
  });
}
