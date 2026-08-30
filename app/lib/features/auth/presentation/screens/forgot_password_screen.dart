import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show kDemoMode;
import 'phone_reset_screen.dart';
import '../../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_text_field.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordResetEmail(_emailController.text);
    if (success && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    ref.listen(authControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sent ? _buildConfirmation(context) : _buildForm(isLoading),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the email associated with your account and we will send a link to reset your password.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // Offered beside the email route rather than instead of
              // it. A parent whose only device is the handset in their
              // pocket often has no email they can reach; a teacher on a
              // school laptop would rather not wait for a text.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PhoneResetScreen(demoMode: kDemoMode),
                ),
              ),
              icon: const Icon(Icons.smartphone_outlined, size: 18),
              label: const Text('Use my phone number instead'),
            ),
          ),
          const SizedBox(height: 24),
          AuthTextField(
            controller: _emailController,
            label: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.email,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isLoading ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: isLoading
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.mark_email_read_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text(
          'If an account exists for that email, a reset link has been sent. Check your inbox.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
