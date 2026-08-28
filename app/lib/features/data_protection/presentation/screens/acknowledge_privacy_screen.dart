import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../controllers/data_protection_controller.dart';
import '../widgets/privacy_notice_body.dart';

/// Shown once, before anything else, until the person says they have
/// read it.
///
/// The whole notice, not a summary with a link. A gate that summarises
/// records people agreeing to the summary, which is worth nothing to the
/// school when somebody later says they were never told.
///
/// There is deliberately no "decline". Declining would mean a student
/// cannot see their own grades, which is not a choice a school can
/// offer and not one this button should pretend to. What the notice
/// gives is the right to ask, object and complain -- and those are on
/// the page, with the officer to take them to.
class AcknowledgePrivacyScreen extends ConsumerStatefulWidget {
  const AcknowledgePrivacyScreen({super.key});

  @override
  ConsumerState<AcknowledgePrivacyScreen> createState() => _AcknowledgePrivacyScreenState();
}

class _AcknowledgePrivacyScreenState extends ConsumerState<AcknowledgePrivacyScreen> {
  bool _readToTheEnd = false;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Enabled once the page has actually been scrolled through. Not a
      // dark pattern in reverse: a button that is live before the text
      // has moved is a button people press without looking, and the
      // record of that press is what the school would be relying on.
      if (!_readToTheEnd &&
          _controller.hasClients &&
          _controller.offset >= _controller.position.maxScrollExtent - 40) {
        setState(() => _readToTheEnd = true);
      }
    });
    // A short notice on a tall screen never scrolls, so there is nothing
    // to reach the end of.
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

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(brandingProvider).valueOrNull ?? SchoolBranding.empty;
    final busy = ref.watch(dataProtectionActionControllerProvider).isLoading;

    ref.listen(dataProtectionActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Before you start'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [PrivacyNoticeBody(branding: branding)],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_readToTheEnd)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Scroll to the end to continue.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy || !_readToTheEnd
                          ? null
                          : () => ref
                              .read(dataProtectionActionControllerProvider.notifier)
                              .acknowledge(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('I have read this'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
