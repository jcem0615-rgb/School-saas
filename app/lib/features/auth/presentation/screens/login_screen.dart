import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../data/remembered_email.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_text_field.dart';
import 'forgot_password_screen.dart';
import '../../../../core/theme/glass.dart';
import '../../../../core/widgets/brand.dart';

/// Entry point of the app for signed-out users. Role/tenant routing after
/// a successful login is handled entirely by the router reacting to
/// [authStateProvider] -- this screen only needs to know "did login
/// succeed," not "where do I go next."
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  /// Ticked by default once an email has been remembered, so somebody
  /// coming back does not have to re-tick it every time to stay
  /// remembered -- and unticking it forgets, which is the only way to
  /// take a shared computer back off the list.
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _restoreRememberedEmail();
  }

  Future<void> _restoreRememberedEmail() async {
    final email = await RememberedEmail.read();
    if (!mounted || email == null) return;
    setState(() {
      _emailController.text = email;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // Written before the attempt rather than after it. Sign-in success
    // redirects immediately -- the router reacts to authStateProvider --
    // so anything queued behind the await runs on a screen that is on its
    // way out. Unticking and then failing to sign in still forgets, which
    // is the right way round for the shared-computer case.
    await RememberedEmail.write(_remember ? _emailController.text : null);

    await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text,
          password: _passwordController.text,
        );
    // Navigation happens automatically via the router listening to
    // authStateProvider; no explicit push needed here.
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              // The one screen that gets the full treatment: blurred, lifted,
              // and the only surface on it. Everywhere else the panes are
              // one of several things on screen and hold back accordingly.
              child: GlassSurface(
                elevated: true,
                radius: 28,
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: LogicClassMark(size: 76)),
                    const SizedBox(height: 14),
                    Text(
                      'LogicClass',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 30,
                            letterSpacing: -0.8,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in with your school-issued credentials',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    AuthTextField(
                      controller: _emailController,
                      label: 'Email',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passwordController,
                      label: 'Password',
                      prefixIcon: Icons.lock_outline,
                      isPassword: true,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Password is required.' : null,
                      onSubmitted: (_) => _submit(),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: isLoading
                                ? null
                                : () => setState(() => _remember = !_remember),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _remember,
                                  onChanged: isLoading
                                      ? null
                                      : (v) => setState(() => _remember = v ?? false),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                Flexible(
                                  child: Text(
                                    'Remember me',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: isLoading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                  ),
                          child: const Text('Forgot password?'),
                        ),
                      ],
                    ),
                    Text(
                      // Said plainly, because "remember me" on a school's
                      // front-desk computer is otherwise read as "keep my
                      // password here".
                      'Fills in your email next time. Your password is never stored.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 24),
                    const PoweredByLogicGrid(),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
