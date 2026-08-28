import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/data_protection/domain/entities/data_request.dart';
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

  test('a family can raise a request and the office sees it', () async {
    final container = await _signedInAs(UserRole.parent);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.dataRequests.value.length;

    final ok = await container.read(dataProtectionActionControllerProvider.notifier).raise(
          kind: DataRequestKind.correction,
          details: 'My phone number on file is the old one.',
        );

    expect(ok, isTrue);
    expect(store.dataRequests.value, hasLength(before + 1));
    final filed = store.dataRequests.value.first;
    expect(filed.kind, DataRequestKind.correction);
    expect(filed.status, DataRequestStatus.open);
    expect(filed.outcome, isNull);
  });

  test('an empty request is refused and nothing is filed', () async {
    final container = await _signedInAs(UserRole.parent);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.dataRequests.value.length;

    final ok = await container.read(dataProtectionActionControllerProvider.notifier).raise(
          kind: DataRequestKind.access,
          details: '   ',
        );

    expect(ok, isFalse);
    expect(store.dataRequests.value, hasLength(before));
  });

  test('the office answers a request and the person who asked sees the answer', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final open = store.dataRequests.value.firstWhere((r) => r.isOpen);

    final ok = await container.read(dataProtectionActionControllerProvider.notifier).close(
          requestId: open.id,
          status: DataRequestStatus.actioned,
          outcome: 'Printed and handed over at the registrar.',
        );

    expect(ok, isTrue);
    final answered = store.dataRequests.value.firstWhere((r) => r.id == open.id);
    expect(answered.status, DataRequestStatus.actioned);
    expect(answered.outcome, 'Printed and handed over at the registrar.');
    expect(answered.handledByName, isNotNull);
    expect(answered.details, open.details, reason: 'the question asked must not change');
  });

  // A school cannot always agree, and a system with nowhere to put a
  // refusal pushes the office into either lying or ignoring it.
  test('a refusal cannot be recorded without a reason', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(dataProtectionActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final open = store.dataRequests.value.firstWhere((r) => r.isOpen);

    final ok = await container.read(dataProtectionActionControllerProvider.notifier).close(
          requestId: open.id,
          status: DataRequestStatus.refused,
          outcome: '',
        );

    expect(ok, isFalse);
    expect(store.dataRequests.value.firstWhere((r) => r.id == open.id).isOpen, isTrue);
  });

  test('the seeded refusal carries its reason', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final refused = container
        .read(demoStoreProvider)
        .dataRequests
        .value
        .firstWhere((r) => r.status == DataRequestStatus.refused);
    expect(refused.outcome, isNotNull);
    expect(refused.outcome, contains('required to keep'));
  });
}
