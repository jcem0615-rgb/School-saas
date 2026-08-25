import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/emergency/domain/entities/emergency_alert.dart';
import 'package:logicclass/features/emergency/presentation/controllers/emergency_controller.dart';
import 'package:logicclass/features/emergency/presentation/screens/parent_alerts_screen.dart';
import 'package:logicclass/features/parent_portal/presentation/screens/parent_dashboard_screen.dart';

/// A parent whose child presses the emergency button gets a push — and
/// push is exactly what cannot be relied on. Permission gets declined, a
/// phone is in a bag on silent, the project has no messaging configured
/// yet. So the in-app path has to work on its own, and it has to work
/// without the parent knowing to go looking for it.
void main() {
  ProviderContainer asParent() {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'parent@demo.ph'),
        );
    return c;
  }

  /// Waits for a provider to settle, for plain `test()` bodies only.
  ///
  /// Never call this inside testWidgets: the widget binding runs on a
  /// fake clock, so a bare Future.delayed there never completes and the
  /// test hangs until its ten-minute timeout. In a widget test,
  /// pumpAndSettle is what advances time.
  Future<T> settled<T>(ProviderContainer c, ProviderListenable<T> p, bool Function(T) until) async {
    final sub = c.listen(p, (_, __) {});
    addTearDown(sub.close);
    for (var i = 0; i < 25 && !until(sub.read()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return sub.read();
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  group('a parent can reach their children\'s alerts', () {
    test('the provider gathers every linked child, newest first', () async {
      final c = asParent();
      final alerts = await settled(c, childrenEmergencyAlertsProvider, (a) => a.isNotEmpty);

      expect(alerts, isNotEmpty);
      final linked = DemoStore.demoAccounts
          .firstWhere((a) => a.email == 'parent@demo.ph')
          .linkedStudentIds ?? const <String>[];
      expect(alerts.every((a) => linked.contains(a.studentId)), isTrue,
          reason: 'a parent must never be shown another family\'s alert');
      for (var i = 1; i < alerts.length; i++) {
        expect(alerts[i - 1].raisedAt.isAfter(alerts[i].raisedAt), isTrue);
      }
    });

    testWidgets('the screen shows the alert and what the school did', (tester) async {
      final c = asParent();
      await pump(tester, c, const ParentAlertsScreen());

      expect(find.textContaining('pressed the emergency button'), findsWidgets);
      expect(find.textContaining('Resolved by the school'), findsOneWidget,
          reason: 'the seeded alert was dealt with, and saying so is the '
              'single most reassuring thing on the screen');
    });

    testWidgets('and offers the school phone numbers without another tap',
        (tester) async {
      // A parent who has just read this is going to call somebody.
      final c = asParent();
      await pump(tester, c, const ParentAlertsScreen());

      expect(find.text('Call the school'), findsOneWidget);
      expect(find.byIcon(Icons.call), findsWidgets);
    });
  });

  group('an unresolved alert is not hidden behind a tap', () {
    testWidgets('no active alert, no banner', (tester) async {
      final c = asParent();
      await pump(tester, c, const ParentDashboardScreen());

      expect(find.textContaining('pressed the emergency button'), findsNothing);
      // But the way in is always there.
      expect(find.byTooltip('Emergency Alerts'), findsOneWidget);
    });

    testWidgets('a live alert puts a banner on the dashboard', (tester) async {
      final c = asParent();

      // The student presses the button while the parent has the app open.
      final store = c.read(demoStoreProvider);
      store.prepend(
        store.emergencyAlerts,
        EmergencyAlert(
          id: 'alert_live',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          userId: 'u_student',
          message: 'Need help',
          raisedAt: DateTime.now(),
        ),
      );
      await pump(tester, c, const ParentDashboardScreen());

      expect(find.text('Miguel Torres pressed the emergency button'), findsOneWidget);
      expect(find.textContaining('who is responding'), findsOneWidget);
    });

    testWidgets('an unacknowledged alert says so, rather than looking handled',
        (tester) async {
      final c = asParent();
      final store = c.read(demoStoreProvider);
      store.prepend(
        store.emergencyAlerts,
        EmergencyAlert(
          id: 'alert_live',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          userId: 'u_student',
          raisedAt: DateTime.now(),
        ),
      );
      await pump(tester, c, const ParentAlertsScreen());

      expect(find.text('Sent to the school. Nobody has picked it up yet.'), findsOneWidget,
          reason: 'a parent reading "raised" would not know whether anyone '
              'has seen it');
    });

    testWidgets('once staff acknowledge, the parent is told who', (tester) async {
      final c = asParent();
      final store = c.read(demoStoreProvider);
      store.prepend(
        store.emergencyAlerts,
        EmergencyAlert(
          id: 'alert_live',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          userId: 'u_student',
          raisedAt: DateTime.now(),
          acknowledgedByName: 'Maria Santos',
          acknowledgedAt: DateTime.now(),
        ),
      );
      await pump(tester, c, const ParentAlertsScreen());

      expect(find.text('Maria Santos from the school is on the way.'), findsOneWidget);
    });
  });
}
