import 'package:flutter/material.dart';

import 'install_prompt_factory.dart';

/// Offers to install the web app, where the browser allows it.
///
/// Renders nothing at all on a phone build, on desktop builds, and in a
/// browser that has already installed this — an "Install" button in an
/// installed app is a button that cannot do anything.
///
/// The offer is re-read on build rather than resolved once, *and* the
/// widget subscribes to the page: the browser fires
/// `beforeinstallprompt` well after first paint, and the sign-in screen
/// is static, so nothing would otherwise rebuild this to notice. Reading
/// on build alone left a button that was correct and never on screen.
class InstallAppButton extends StatefulWidget {
  /// Takes its colours from the theme, and used to take a
  /// `onDarkSurface` flag from the caller instead.
  ///
  /// The sign-in screen passed it, which pinned the text to white -- and
  /// the app has two themes. In the dark one that is white on deep blue
  /// and reads at 15.7:1. In the light one the sign-in pane is white
  /// glass over a pale sky, so it was **white on white, at 1.02:1**: the
  /// button rendered, occupied space, and could not be seen. A device in
  /// light mode is the common case.
  ///
  /// There is no flag now. A caller cannot be asked to know what the
  /// theme already knows.
  const InstallAppButton({super.key, this.debugPrompt});

  /// Stands in for the browser, so a test can render the branches that
  /// only exist in one.
  ///
  /// On the VM the real prompt always offers nothing, so both visible
  /// branches -- the button and the iOS instructions line -- are
  /// unreachable from a widget test without this. That is how the
  /// white-on-white went unnoticed: the only thing a test could see was
  /// an empty box.
  @visibleForTesting
  final InstallPrompt? debugPrompt;

  @override
  State<InstallAppButton> createState() => _InstallAppButtonState();
}

class _InstallAppButtonState extends State<InstallAppButton> {
  late final InstallPrompt _prompt;
  late final void Function() _stopListening;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _prompt = widget.debugPrompt ?? createInstallPrompt();
    _stopListening = _prompt.listen(() {
      // The event can land while this screen is going away -- a sign-in
      // that succeeded a moment earlier takes the route with it.
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // An action, so it takes the scheme's action colour. Measured against
    // the sign-in pane it reads at 6.3:1 in light and 9.3:1 in dark --
    // see install_contrast_test.dart, which pins both.
    final action = theme.colorScheme.primary;
    // Secondary text, so the quieter one. 4.6:1 and 5.9:1 at this alpha.
    final quiet = theme.colorScheme.onSurfaceVariant;

    return switch (_prompt.offer) {
      InstallOffer.none => const SizedBox.shrink(),
      InstallOffer.instructions => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.ios_share, size: 16, color: quiet),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  // No button, because Safari gives nothing to press.
                  // Saying where the real one is beats a fake one.
                  'To install: tap Share, then Add to Home Screen.',
                  style: theme.textTheme.bodySmall?.copyWith(color: quiet),
                ),
              ),
            ],
          ),
        ),
      InstallOffer.prompt => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextButton.icon(
            onPressed: _busy ? null : _install,
            style: TextButton.styleFrom(foregroundColor: action),
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
