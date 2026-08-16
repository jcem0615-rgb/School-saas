import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/admin_portal/presentation/controllers/admin_controller.dart';
import 'package:school_saas/features/emergency/presentation/controllers/emergency_controller.dart';

/// The emergency features are the ones most likely to be used exactly
/// once, under stress, by somebody who has never used them before. That
/// is a reason for more care than usual, not less.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  group('emergency numbers', () {
    test('every role can read them', () async {
      // The whole point. A number a student cannot reach during a fire is
      // not a safety feature, so this asserts the reach rather than one
      // convenient role.
      for (final role in UserRole.values.where((r) => r != UserRole.owner)) {
        final container = await signedInAs(role);
        final contacts = await container.read(emergencyContactsProvider.future);
        expect(contacts, isNotEmpty, reason: '${role.displayName} must see the numbers');
        expect(
          contacts.map((c) => c.label),
          contains('BFP - San Nicolas Fire Station'),
          reason: '${role.displayName} sees the fire station',
        );
      }
    });

    test('they come back in the order the school set', () async {
      final container = await signedInAs(UserRole.student);
      final contacts = await container.read(emergencyContactsProvider.future);
      final orders = contacts.map((c) => c.sortOrder).toList();
      expect(orders, orderedEquals(List.of(orders)..sort()),
          reason: 'whoever should be called first belongs at the top');
    });

    test('an admin can add one', () async {
      final container = await signedInAs(UserRole.admin);
      final sub = container.listen(emergencyActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);
      final before = store.emergencyContacts.value.length;

      final ok = await container.read(emergencyActionControllerProvider.notifier).saveContact(
            label: 'Batangas Medical Center',
            phone: '(043) 555 0123',
            sortOrder: 4,
          );

      expect(ok, isTrue);
      expect(store.emergencyContacts.value.length, before + 1);
    });

    test('a number with no name or no digits is refused', () async {
      // A row that looks like help and is not is worse than a short list.
      final container = await signedInAs(UserRole.admin);
      final sub = container.listen(emergencyActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(emergencyActionControllerProvider.notifier);

      expect(await notifier.saveContact(label: '', phone: '911', sortOrder: 0), isFalse);
      expect(await notifier.saveContact(label: 'PNP', phone: '  ', sortOrder: 0), isFalse);
    });

    test('a written number is turned into something a dialler accepts', () async {
      // PH numbers get written a dozen ways; a tel: link built from the
      // raw string fails on the punctuation.
      final container = await signedInAs(UserRole.student);
      final contacts = await container.read(emergencyContactsProvider.future);
      final bfp = contacts.firstWhere((c) => c.label.startsWith('BFP'));
      expect(bfp.phone, '(043) 555 0161');
      expect(bfp.dialable, '0435550161');
    });
  });

  group('the emergency button', () {
    test('a student can raise an alert', () async {
      final container = await signedInAs(UserRole.student);
      final sub = container.listen(emergencyActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);

      final ok = await container.read(emergencyActionControllerProvider.notifier).raiseAlert(
            studentId: 'stu_001',
            studentName: 'Miguel Torres',
            section: 'Grade 10 - Rizal',
            message: 'Fell on the stairs by the canteen.',
          );

      expect(ok, isTrue);
      expect(store.emergencyAlerts.value, hasLength(1));
      final alert = store.emergencyAlerts.value.single;
      expect(alert.studentName, 'Miguel Torres');
      expect(alert.isActive, isTrue);
      expect(alert.isAcknowledged, isFalse);
    });

    test('staff see it and can acknowledge, then resolve', () async {
      final container = await signedInAs(UserRole.student);
      final studentSub = container.listen(emergencyActionControllerProvider, (_, __) {});
      addTearDown(studentSub.close);
      await container.read(emergencyActionControllerProvider.notifier).raiseAlert(
            studentId: 'stu_001',
            studentName: 'Miguel Torres',
            section: 'Grade 10 - Rizal',
          );

      final store = container.read(demoStoreProvider);
      final id = store.emergencyAlerts.value.single.id;
      final notifier = container.read(emergencyActionControllerProvider.notifier);

      // Acknowledging is separate from resolving: "I have seen this and I
      // am coming" is what the student needs first.
      expect(await notifier.acknowledgeAlert(id), isTrue);
      var alert = store.emergencyAlerts.value.single;
      expect(alert.isAcknowledged, isTrue);
      expect(alert.isActive, isTrue, reason: 'acknowledged is not the same as over');

      expect(await notifier.resolveAlert(alertId: id, note: 'Taken to the clinic.'), isTrue);
      alert = store.emergencyAlerts.value.single;
      expect(alert.isResolved, isTrue);
      expect(alert.isActive, isFalse);
      expect(alert.resolutionNote, 'Taken to the clinic.');
    });

    test('an alert with no message still goes', () async {
      // Somebody in trouble may not be able to type. The button has to
      // work with nothing filled in.
      final container = await signedInAs(UserRole.student);
      final sub = container.listen(emergencyActionControllerProvider, (_, __) {});
      addTearDown(sub.close);

      final ok = await container.read(emergencyActionControllerProvider.notifier).raiseAlert(
            studentId: 'stu_001',
            studentName: 'Miguel Torres',
            section: 'Grade 10 - Rizal',
            message: '   ',
          );

      expect(ok, isTrue);
      expect(container.read(demoStoreProvider).emergencyAlerts.value.single.message, isNull);
    });
  });

  group('advisory class', () {
    test('the section has exactly one adviser, and it is a real teacher', () async {
      // The alert fan-out resolves recipients from this. A section with
      // no adviser means an alert that reaches only the parents.
      final container = await signedInAs(UserRole.admin);
      final store = container.read(demoStoreProvider);
      final advisers = store.assignments.value
          .where((a) => a.section == 'Grade 10 - Rizal' && a.isAdviser)
          .toList();

      expect(advisers, hasLength(1));
      expect(advisers.single.teacherName, 'Maria Santos');
      expect(advisers.single.teacherId, isNotEmpty);
    });

    test('an ordinary subject assignment is not an advisory', () async {
      final container = await signedInAs(UserRole.admin);
      final store = container.read(demoStoreProvider);
      final science = store.assignments.value
          .firstWhere((a) => a.subject == 'Science' && a.section == 'Grade 10 - Rizal');
      expect(science.isAdviser, isFalse);
    });

    test('an admin can hand the advisory to somebody', () async {
      final container = await signedInAs(UserRole.admin);
      final sub = container.listen(adminActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);

      final ok = await container.read(adminActionControllerProvider.notifier).createTeacherAssignment(
            teacherId: 'u_faculty2',
            teacherName: 'Dennis Pascual',
            subject: 'Advisory',
            section: 'BSCS 3-A',
            schoolYear: '2026-2027',
            isAdviser: true,
          );

      expect(ok, isTrue);
      final created = store.assignments.value.firstWhere((a) => a.section == 'BSCS 3-A' && a.isAdviser);
      expect(created.teacherName, 'Dennis Pascual');
    });
  });
}
