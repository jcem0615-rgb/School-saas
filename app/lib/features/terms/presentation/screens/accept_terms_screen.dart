import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/terms_of_service.dart';
import '../controllers/terms_controller.dart';

/// Shown once, before anything else, until the person accepts.
///
/// The whole agreement, not a summary with a link. A gate that summarises
/// records people agreeing to the summary, which is worth nothing to the
/// school when somebody later says they were never told.
///
/// Unlike the privacy notice, this one **does** offer a way out, and the
/// difference is the point. A notice is given; an agreement is entered
/// into, and one nobody can decline is not an agreement. Declining signs
/// you out -- the account is untouched, nothing is recorded against it,
/// and the conversation that follows is with the school rather than with
/// this screen.
class AcceptTermsScreen extends ConsumerStatefulWidget {
  const AcceptTermsScreen({super.key});

  @override
  ConsumerState<AcceptTermsScreen> createState() => _AcceptTermsScreenState();
}

class _AcceptTermsScreenState extends ConsumerState<AcceptTermsScreen> {
  bool _readToTheEnd = false;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Live only once the page has actually been scrolled through. A
      // button that is pressable before the text has moved is one people
      // press without looking, and that press is what the school would
      // be relying on later.
      if (!_readToTheEnd &&
          _controller.hasClients &&
          _controller.offset >= _controller.position.maxScrollExtent - 40) {
        setState(() => _readToTheEnd = true);
      }
    });
    // A tall screen may not scroll at all, leaving nothing to reach the
    // end of.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.position.maxScrollExtent <= 0) {
        setState(() => _readToTheEnd = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final ok = await ref.read(termsControllerProvider.notifier).accept();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('That could not be recorded. Try again.'),
      ));
  }

  Future<void> _decline() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out instead?'),
        content: const Text(
          'Your account stays exactly as it is and nothing is recorded '
          'against it. You will be asked again next time you sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (leave == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = ref.watch(termsControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Before you start'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  Text(TermsOfService.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Version ${TermsOfService.version}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 14),
                  Text(TermsOfService.preamble, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  for (final clause in TermsOfService.clauses) ...[
                    Text(clause.heading,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(clause.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                  ],
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    TermsOfService.privacyPointer,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_readToTheEnd)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Scroll to the end to continue.',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  FilledButton(
                    onPressed: (!_readToTheEnd || busy) ? null : _accept,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('I accept these terms'),
                  ),
                  TextButton(
                    onPressed: busy ? null : _decline,
                    child: const Text('I do not accept - sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
