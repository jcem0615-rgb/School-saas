import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/core/widgets/confirm_delete_dialog.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/admin_dashboard_screen.dart';
import 'package:logicclass/features/emergency/presentation/controllers/emergency_controller.dart';
import 'package:logicclass/features/emergency/presentation/screens/emergency_contacts_screen.dart';

/// The PNP number, the fire station, the clinic. An Admin was always
/// allowed to edit these — firestore.rules says so and the screen's own
/// editor list says so — but the only way in was through Profile, which
/// is where you look for your own settings, not for a list the whole
/// school depends on. A number that is wrong because nobody could find
/// the screen to fix it is the same as no number at all.
void main() {
  ProviderContainer signedInAs(String email) {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == email),
        );
    return c;
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

  group('finding the screen', () {
    testWidgets('the admin dashboard offers Emergency Numbers', (tester) async {
      await pump(tester, signedInAs('admin@demo.ph'), const AdminDashboardScreen());
      expect(find.text('Emergency Numbers'), findsOneWidget);
      // Distinct from the alerts raised against them, which is a
      // different screen and was already there.
      expect(find.text('Emergency Alerts'), findsOneWidget);
    });
  });

  group('who may edit', () {
    testWidgets('an admin gets add, edit and delete', (tester) async {
      await pump(tester, signedInAs('admin@demo.ph'), const EmergencyContactsScreen());

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(RowActionsMenu), findsWidgets);
      expect(find.textContaining('PNP'), findsOneWidget);
    });

    testWidgets('a student reads them and can dial, but cannot edit', (tester) async {
      // The numbers are readable by everyone with no scoping at all —
      // a number a student cannot reach during a fire is not a safety
      // feature. Editing is another matter.
      await pump(tester, signedInAs('student@demo.ph'), const EmergencyContactsScreen());

      expect(find.textContaining('PNP'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(RowActionsMenu), findsNothing);
      expect(find.byIcon(Icons.call), findsWidgets);
    });

  });

  group('editing a number', () {
    // Plain tests, not testWidgets. saveContact goes through the demo
    // repository's _latency(), which is a real Future.delayed -- and
    // inside a widget test the clock is fake, so it would never complete
    // and the test would hang until its ten-minute timeout.

    test('an admin can change the PNP number and it sticks', () async {
      final c = signedInAs('admin@demo.ph');
      final store = c.read(demoStoreProvider);
      final pnp = store.emergencyContacts.value.firstWhere((x) => x.label.contains('PNP'));

      final ok = await c.read(emergencyActionControllerProvider.notifier).saveContact(
            contactId: pnp.id,
            label: 'PNP - San Nicolas Police Station',
            phone: '(043) 555 0199',
            notes: 'Ask for the desk officer',
            sortOrder: pnp.sortOrder,
          );

      expect(ok, isTrue);
      final after = store.emergencyContacts.value.firstWhere((x) => x.id == pnp.id);
      expect(after.phone, '(043) 555 0199');
      expect(after.notes, 'Ask for the desk officer');
    });

    test('and can add one the school did not have', () async {
      final c = signedInAs('admin@demo.ph');
      final store = c.read(demoStoreProvider);
      final before = store.emergencyContacts.value.length;

      final ok = await c.read(emergencyActionControllerProvider.notifier).saveContact(
            label: 'Barangay Hall',
            phone: '(043) 555 0123',
            sortOrder: 5,
          );

      expect(ok, isTrue);
      expect(store.emergencyContacts.value, hasLength(before + 1));
      expect(store.emergencyContacts.value.any((x) => x.label == 'Barangay Hall'), isTrue);
    });
  });
}
