import 'package:flutter/material.dart';

import 'install_prompt_factory.dart';

/// Offers to install the web app, where the browser allows it.
///
/// Renders nothing at all on a phone build, on desktop builds, and in a
/// browser that has already installed this — an "Install" button in an
/// installed app is a button that cannot do anything.
///
/// The offer is re-read on build rather than resolved once: the browser
/// fires `beforeinstallprompt` some time after load, so a widget that
/// decided at construction would say "no" forever on a fast first paint.
class InstallAppButton extends StatefulWidget {
  /// Set on a dark ground (the sign-in screen) so the text stays legible
  /// against it rather than taking the light theme's foreground.
  final bool onDarkSurface;

  const InstallAppButton({super.key, this.onDarkSurface = false});

  @override
  State<InstallAppButton> createState() => _InstallAppButtonState();
}

class _InstallAppButtonState extends State<InstallAppButton> {
  final _prompt = createInstallPrompt();
  bool _busy = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tint = widget.onDarkSurface ? Colors.white : theme.colorScheme.onSurface;

    return switch (_prompt.offer) {
      InstallOffer.none => const SizedBox.shrink(),
      InstallOffer.instructions => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.ios_share, size: 16, color: tint.withValues(alpha: .75)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  // No button, because Safari gives nothing to press.
                  // Saying where the real one is beats a fake one.
                  'To install: tap Share, then Add to Home Screen.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tint.withValues(alpha: .75)),
                ),
              ),
            ],
          ),
        ),
      InstallOffer.prompt => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextButton.icon(
            onPressed: _busy ? null : _install,
            style: TextButton.styleFrom(foregroundColor: tint),
            icon: const Icon(Icons.install_mobile, size: 18),
            label: const Text('Install the app'),
          ),
        ),
    };
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    final accepted = await _prompt.show();
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Accepted or dismissed, the event is spent either way -- the
      // browser will not hand out a second one this visit. Leaving the
      // button on screen would leave one that no longer works.
      _done = true;
    });
    if (!accepted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Installed. Open LogicClass from your home screen.')),
      );
  }
}
