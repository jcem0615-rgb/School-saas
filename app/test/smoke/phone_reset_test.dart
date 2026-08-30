import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/features/auth/data/phone/phone_verifier_impl.dart';
import 'package:logicclass/features/auth/presentation/controllers/phone_reset_controller.dart';

/// Recovering an account with the phone in your hand.
///
/// The three steps have to happen in order, and each one has to refuse
/// what comes before it. Runs against the demo verifier, which stands in
/// for Firebase Phone Auth -- what it cannot prove is that a real SMS
/// arrives, only that the flow around it holds together.
void main() {
  PhoneResetController controllerOf(ProviderContainer container) {
    final sub = container.listen(phoneResetControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(phoneResetControllerProvider.notifier);
  }

  ProviderContainer demoContainer() {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    return container;
  }

  group('the steps', () {
    test('start at the number', () {
      final container = demoContainer();
      expect(
        container.read(phoneResetControllerProvider).stage,
        PhoneResetStage.number,
      );
    });

    test('a blank number is refused rather than sent', () async {
      final container = demoContainer();
      final controller = controllerOf(container);

      await controller.sendCode('   ');

      final state = container.read(phoneResetControllerProvider);
      expect(state.stage, PhoneResetStage.number);
      expect(state.error, isNotNull);
    });

    test('sending a code moves on, and remembers the number', () async {
      final container = demoContainer();
      final controller = controllerOf(container);

      await controller.sendCode('0917 555 0100');

      final state = container.read(phoneResetControllerProvider);
      expect(state.stage, PhoneResetStage.code);
      // Shown back on the next screen, so a mistyped digit is found
      // there rather than by waiting for a text that never comes.
      expect(state.phoneNumber, '0917 555 0100');
      expect(state.error, isNull);
    });

    test('a wrong code does not get past the code step', () async {
      final container = demoContainer();
      final controller = controllerOf(container);
      await controller.sendCode('09175550100');

      await controller.confirmCode('000000');

      final state = container.read(phoneResetControllerProvider);
      expect(state.stage, PhoneResetStage.code);
      expect(state.error, contains('does not match'));
    });

    test('the right code reaches the password step', () async {
      final container = demoContainer();
      final controller = controllerOf(container);
      await controller.sendCode('09175550100');

      await controller.confirmCode(DemoPhoneVerifier.demoCode);

      final state = container.read(phoneResetControllerProvider);
      expect(state.stage, PhoneResetStage.password);
      expect(state.error, isNull);
    });

    test('and setting the password finishes it', () async {
      final container = demoContainer();
      final controller = controllerOf(container);
      await controller.sendCode('09175550100');
      await controller.confirmCode(DemoPhoneVerifier.demoCode);

      await controller.setPassword('a-new-password');

      expect(
        container.read(phoneResetControllerProvider).stage,
        PhoneResetStage.finished,
      );
    });
  });

  group('the number people actually type', () {
    /// The demo verifier records nothing, so what reaches Firebase is
    /// checked through the one thing that is observable: the flow
    /// accepting the form and moving on. The conversion itself is
    /// asserted below through the controller's own static.
    test('is converted to the international form Firebase wants', () {
      // A Philippine mobile is written 0917... on every form in the
      // country and +63917... by every phone API.
      expect(PhoneResetController.toInternationalForTest('09175550100'),
          '+639175550100');
      expect(PhoneResetController.toInternationalForTest('0917 555 0100'),
          '+639175550100');
      expect(PhoneResetController.toInternationalForTest('+639175550100'),
          '+639175550100');
      expect(PhoneResetController.toInternationalForTest('639175550100'),
          '+639175550100');
      expect(PhoneResetController.toInternationalForTest('9175550100'),
          '+639175550100');
    });

    test('leaves a foreign number alone rather than mangling it', () {
      expect(PhoneResetController.toInternationalForTest('+14155550100'),
          '+14155550100');
    });
  });
}
