import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/phone/phone_verifier_impl.dart' show DemoPhoneVerifier;
import '../controllers/phone_reset_controller.dart';
import '../widgets/auth_text_field.dart';

/// Recovering an account with the phone in your hand.
///
/// Email reset already existed and is still there, but it assumes the
/// person has an email account they can reach, which for a parent whose
/// only device is the handset in their pocket is often not true. The SIM
/// is the thing they definitely have.
///
/// Three steps in one screen rather than three routes: somebody halfway
/// through a recovery does not want a back stack, and a code that
/// expires while they are on a different page is a code they have to ask
/// for again.
class PhoneResetScreen extends ConsumerStatefulWidget {
  /// True when the app is running against the in-memory demo, where no
  /// SMS is sent and the code is fixed. Passed in rather than detected
  /// here, so this screen has no opinion about how the app was built.
  final bool demoMode;

  const PhoneResetScreen({super.key, this.demoMode = false});

  @override
  ConsumerState<PhoneResetScreen> createState() => _PhoneResetScreenState();
}

class _PhoneResetScreenState extends ConsumerState<PhoneResetScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // The phone session is ended by the controller's own dispose, not
    // here: `ref` is already gone by the time this runs.
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phoneResetControllerProvider);
    final controller = ref.read(phoneResetControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reset by phone')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.demoMode)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        // A demo that asked for a code nobody can
                        // receive is a dead end.
                        'This is a demo: no text message is sent, and the '
                        'code is ${DemoPhoneVerifier.demoCode}.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  switch (state.stage) {
                    PhoneResetStage.number => _numberStep(state, controller),
                    PhoneResetStage.code => _codeStep(state, controller),
                    PhoneResetStage.password => _passwordStep(state, controller),
                    PhoneResetStage.finished => _finishedStep(),
                  },
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      state.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberStep(PhoneResetState state, PhoneResetController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter the mobile number your school has on your record. We will '
          'text you a code.',
        ),
        const SizedBox(height: 20),
        AuthTextField(
          controller: _phone,
          label: 'Mobile number',
          prefixIcon: Icons.smartphone_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Text(
          // Said here so nobody types it wrong: the app converts, and
          // the school's records are written both ways.
          'Either 09171234567 or +639171234567 is fine.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: state.busy ? null : () => controller.sendCode(_phone.text),
          child: state.busy ? const _Spinner() : const Text('Send me a code'),
        ),
      ],
    );
  }

  Widget _codeStep(PhoneResetState state, PhoneResetController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter the code sent to ${state.phoneNumber}.'),
        const SizedBox(height: 20),
        AuthTextField(
          controller: _code,
          label: '6-digit code',
          prefixIcon: Icons.dialpad_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: state.busy ? null : () => controller.confirmCode(_code.text),
          child: state.busy ? const _Spinner() : const Text('Check the code'),
        ),
        TextButton(
          // A mistyped digit is the common failure, and it is cheaper to
          // go back than to wait for a text that is never coming.
          onPressed: state.busy ? null : () => controller.sendCode(state.phoneNumber),
          child: const Text('Send it again'),
        ),
      ],
    );
  }

  Widget _passwordStep(PhoneResetState state, PhoneResetController controller) {
    return Form(
      key: _passwordKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your number is verified. Choose a new password.'),
          const SizedBox(height: 20),
          AuthTextField(
            controller: _password,
            label: 'New password',
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            validator: (value) => (value == null || value.length < 8)
                ? 'At least 8 characters.'
                : null,
          ),
          const SizedBox(height: 12),
          AuthTextField(
            controller: _confirm,
            label: 'Type it again',
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            textInputAction: TextInputAction.done,
            validator: (value) =>
                value == _password.text ? null : 'These do not match.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: state.busy
                ? null
                : () {
                    if (!_passwordKey.currentState!.validate()) return;
                    controller.setPassword(_password.text);
                  },
            child: state.busy ? const _Spinner() : const Text('Set my password'),
          ),
        ],
      ),
    );
  }

  Widget _finishedStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Password set', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          // Named plainly, because it will surprise somebody: everything
          // signed in on another device has been signed out. That is the
          // point of a recovery.
          'Sign in with your email and the password you just chose. Anywhere '
          'else that was signed in to this account has been signed out.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
