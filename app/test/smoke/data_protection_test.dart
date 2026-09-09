import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/data_protection/domain/entities/privacy_notice.dart';
import 'package:logicclass/features/data_protection/presentation/controllers/data_protection_controller.dart';

Future<ProviderContainer> _signedInAs(UserRole role) async {
  final container = ProviderContainer(overrides: demoOverrides());
  // Subscribed, not read. needsPrivacyAcknowledgementProvider answers
  // "no" while auth state is still loading -- the right default, since
  // nobody should be gated before they have been identified -- and a
  // cold read of a stream provider is exactly that state. The running
  // app always has a listener on it; a test has to say so.
  container.listen(authStateProvider, (_, __) {});
  container.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('a new sign-in owes an acknowledgement, and stops owing one after giving it', () async {
    final container = await _signedInAs(UserRole.student);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    expect(container.read(needsPrivacyAcknowledgementProvider), isTrue);

    expect(
      await container.read(dataProtectionActionControllerProvider.notifier).acknowledge(),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container.read(needsPrivacyAcknowledgementProvider),
      isFalse,
      reason: 'the gate has to open off the record, not off a screen dismissing itself',
    );
  });

  // A flag would record the people who agreed to the old wording as
  // having agreed to the new one.
  test('an older acknowledged version still owes a new one', () async {
    final container = await _signedInAs(UserRole.student);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);

    store.currentUser.add(
      store.currentUser.value!.copyWith(privacyNoticeVersion: PrivacyNotice.version - 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(needsPrivacyAcknowledgementProvider), isTrue);
  });

  test('the acknowledgement survives a role switch and back', () async {
    final container = await _signedInAs(UserRole.student);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final auth = container.read(demoAuthRepositoryProvider);

    await container.read(dataProtectionActionControllerProvider.notifier).acknowledge();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    auth.signInAs(DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    auth.signInAs(DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(needsPrivacyAcknowledgementProvider), isFalse);
  });
}
