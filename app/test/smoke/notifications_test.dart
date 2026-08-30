import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/guidance_portal/domain/entities/summons.dart';
import 'package:logicclass/features/guidance_portal/presentation/controllers/guidance_controller.dart';
import 'package:logicclass/features/notifications/domain/entities/app_notification.dart';
import 'package:logicclass/features/notifications/presentation/controllers/notifications_controller.dart';

/// What a family is actually told, and what they are not.
///
/// Everything here runs against the demo repositories, which mirror what
/// the Cloud Functions do server-side (onSummonsWritten.ts, deliver.ts).
/// That does not prove the trigger works -- only a deployment can -- but
/// it does prove the thing the trigger and the demo agree on: who a
/// summons is delivered to, and that it is delivered once.
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

  List<AppNotification> inboxOf(DemoStore store, String uid) =>
      store.notifications.value[uid] ?? const [];

  group('a summons', () {
    test('reaches the student and the parent, and nobody else', () async {
      final container = await signedInAs(UserRole.guidance);
      final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);

      final studentBefore = inboxOf(store, 'u_student').length;
      final parentBefore = inboxOf(store, 'u_parent').length;
      final registrarBefore = inboxOf(store, 'u_registrar').length;

      final ok = await container
          .read(guidanceActionControllerProvider.notifier)
          .createSummons(
            // stu_001 is Miguel Torres, whose own account is u_student and
            // whose parent u_parent is linked to.
            studentId: 'stu_001',
            studentName: 'Miguel Torres',
            reason: 'Repeated tardiness',
            scheduledDate: DateTime.now().add(const Duration(days: 2)),
          );
      expect(ok, isTrue);

      expect(inboxOf(store, 'u_student').length, studentBefore + 1);
      expect(inboxOf(store, 'u_parent').length, parentBefore + 1);
      // A summons is between the guidance office and one family. The
      // registrar has no business being told about it, and the office
      // that issued it does not need telling about its own decision --
      // both keep whatever was already in their inbox and gain nothing.
      expect(inboxOf(store, 'u_registrar').length, registrarBefore);
      expect(
        inboxOf(store, 'u_guidance').where((n) => n.kind == NotificationKind.summons),
        isEmpty,
      );

      final delivered = inboxOf(store, 'u_parent').first;
      expect(delivered.kind, NotificationKind.summons);
      expect(delivered.isRead, isFalse);
      expect(delivered.body, contains('Miguel Torres'));
      expect(delivered.body, contains('Repeated tardiness'));
    });

    test('does not reach a family it is not about', () async {
      final container = await signedInAs(UserRole.guidance);
      final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);
      final studentBefore = inboxOf(store, 'u_student').length;

      // stu_004 is somebody else's child entirely.
      await container.read(guidanceActionControllerProvider.notifier).createSummons(
            studentId: 'stu_004',
            studentName: 'Paolo Ramirez',
            reason: 'Follow-up',
            scheduledDate: DateTime.now().add(const Duration(days: 2)),
          );

      expect(inboxOf(store, 'u_student').length, studentBefore);
    });

    test('cancelling tells them again, rather than silently going away',
        () async {
      final container = await signedInAs(UserRole.guidance);
      final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);

      // sum_001 is Paolo Ramirez's, pending, in the seed data.
      final before = inboxOf(store, 'u_student').length;
      await container
          .read(guidanceActionControllerProvider.notifier)
          .updateSummonsStatus(
            summonsId: 'sum_003',
            status: SummonsStatus.cancelled,
          );

      final after = inboxOf(store, 'u_student');
      expect(after.length, before + 1);
      expect(after.first.title, contains('cancelled'));
      expect(after.first.body, contains('nothing to attend'));
    });

    test('completing one says nothing -- the student was there', () async {
      final container = await signedInAs(UserRole.guidance);
      final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);
      final before = inboxOf(store, 'u_student').length;

      await container
          .read(guidanceActionControllerProvider.notifier)
          .updateSummonsStatus(
            summonsId: 'sum_003',
            status: SummonsStatus.completed,
          );

      expect(inboxOf(store, 'u_student').length, before);
    });
  });

  group('the inbox', () {
    test('shows this account its own notifications and not another\'s',
        () async {
      final parent = await signedInAs(UserRole.parent);
      final parentItems =
          await parent.read(notificationsProvider.future);
      expect(parentItems, isNotEmpty);

      final registrar = await signedInAs(UserRole.registrar);
      final registrarItems =
          await registrar.read(notificationsProvider.future);

      // Both have something; neither has the other's summons.
      expect(
        parentItems.any((n) => n.kind == NotificationKind.summons),
        isTrue,
      );
      expect(
        registrarItems.any((n) => n.kind == NotificationKind.summons),
        isFalse,
      );
    });

    test('counts what is unread, and stops when it is all read', () async {
      final container = await signedInAs(UserRole.parent);
      final sub = container.listen(notificationsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(notificationsProvider.future);

      expect(container.read(unreadNotificationCountProvider), greaterThan(0));

      await container
          .read(notificationsActionControllerProvider.notifier)
          .markAllRead();
      await container.read(notificationsProvider.future);

      expect(container.read(unreadNotificationCountProvider), 0);
    });

    test('marking one read leaves the others alone', () async {
      final container = await signedInAs(UserRole.parent);
      final sub = container.listen(notificationsProvider, (_, __) {});
      addTearDown(sub.close);
      final items = await container.read(notificationsProvider.future);
      final before = container.read(unreadNotificationCountProvider);
      expect(items.length, greaterThan(1));

      await container
          .read(notificationsActionControllerProvider.notifier)
          .markRead(items.first.id);
      await container.read(notificationsProvider.future);

      expect(container.read(unreadNotificationCountProvider), before - 1);
    });

    test('a staff member marking theirs read does not touch a family\'s',
        () async {
      final container = await signedInAs(UserRole.registrar);
      final sub = container.listen(notificationsProvider, (_, __) {});
      addTearDown(sub.close);
      final store = container.read(demoStoreProvider);
      await container.read(notificationsProvider.future);

      final familyUnreadBefore =
          inboxOf(store, 'u_parent').where((n) => !n.isRead).length;

      await container
          .read(notificationsActionControllerProvider.notifier)
          .markAllRead();

      expect(
        inboxOf(store, 'u_parent').where((n) => !n.isRead).length,
        familyUnreadBefore,
      );
    });
  });
}
