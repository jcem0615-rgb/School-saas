import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import 'package:logicclass/features/system_check/presentation/controllers/system_check_controller.dart';

/// In demo mode the preflight must refuse to say anything is ready.
///
/// This is the one place where the demo deliberately does not behave
/// like the real app, and the test exists because the tempting bug is
/// the opposite: a demo repository that cheerfully returns all-green and
/// a green light that means nothing.
void main() {
  test('demo mode reports that nothing was checked', () async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, __) {});
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final sub = container.listen(systemCheckControllerProvider, (_, __) {});
    addTearDown(sub.close);

    await container.read(systemCheckControllerProvider.notifier).run();
    final report = container.read(systemCheckControllerProvider).valueOrNull;

    expect(report, isNotNull);
    expect(report!.demoMode, isTrue);
    expect(report.isReady, isFalse);
    expect(report.headline, 'Nothing was checked');
    expect(
      report.checks,
      isEmpty,
      reason: 'demo mode has nothing to check, and must not invent results',
    );
  });

  test('nothing runs until it is asked to', () async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, __) {});
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.admin),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final sub = container.listen(systemCheckControllerProvider, (_, __) {});
    addTearDown(sub.close);

    // The probes call twelve functions and write to Storage. Opening the
    // screen must not do that to a live deployment.
    expect(container.read(systemCheckControllerProvider).valueOrNull, isNull);
  });
}
