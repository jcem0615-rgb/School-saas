import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';

/// Balance is the one field a registrar edits that does NOT go through an
/// ordinary document update -- firestore.rules keeps it server-only, so the
/// write travels controller -> usecase -> repository -> callable. This
/// checks the value actually lands, which clicking through the UI could not
/// confirm.
void main() {
  test('setting a balance updates the student record', () async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );

    // Sign-in has to settle before the controller is read. The demo
    // repositories ref.watch(authStateProvider) so that a role switch
    // re-subscribes every dependent stream -- which also means the auth
    // emission rebuilds the repository, and with it the autoDispose
    // controller. Reading the notifier before that lands hands back an
    // instance that is disposed mid-write.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(registrarActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final target = store.students.value.firstWhere((s) => s.id == 'stu_005');
    expect(target.balance, 24000, reason: 'seed precondition');

    final ok = await container
        .read(registrarActionControllerProvider.notifier)
        .setStudentBalance(
          studentId: 'stu_005',
          balance: 30000,
          remarks: 'Second semester assessment',
        );

    expect(ok, isTrue, reason: 'the write should succeed');
    expect(
      store.students.value.firstWhere((s) => s.id == 'stu_005').balance,
      30000,
      reason: 'the new balance must be visible to everything reading the store',
    );
  });

  test('a blank reason is rejected', () async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(registrarActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final ok = await container
        .read(registrarActionControllerProvider.notifier)
        .setStudentBalance(studentId: 'stu_005', balance: 30000, remarks: '   ');

    expect(ok, isFalse);

    final store = container.read(demoStoreProvider);
    expect(
      store.students.value.firstWhere((s) => s.id == 'stu_005').balance,
      24000,
      reason: 'a rejected edit must not change the balance',
    );
  });
}
