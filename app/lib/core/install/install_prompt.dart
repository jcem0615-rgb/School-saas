/// Whether this build can offer to install itself, and how.
enum InstallOffer {
  /// Not a browser, or already running as an installed app. Nothing to
  /// offer -- a button here would install what is already installed.
  none,

  /// The browser has told us it would accept an install prompt. One tap.
  prompt,

  /// iOS Safari. It never fires `beforeinstallprompt` and gives no API to
  /// trigger the sheet, so the only honest thing is to say where the
  /// button is: Share, then Add to Home Screen. A button that did
  /// nothing would be worse than instructions.
  instructions,
}

/// Asks the browser to install the app.
///
/// The manifest has always made this installable; what was missing is
/// anything that asks. Browsers hide the affordance in a menu, so a
/// parent told "it works like an app" has no way to find out that it
/// does.
abstract class InstallPrompt {
  const InstallPrompt();

  /// What can be offered right now. Re-read rather than cached: the
  /// browser fires `beforeinstallprompt` some time after load, so a
  /// screen built early would otherwise decide "no" forever.
  InstallOffer get offer;

  /// Fires the browser's install prompt.
  ///
  /// True when the person accepted. False when they dismissed it, or
  /// when there was no prompt to fire -- the event is single-use, so a
  /// second call after a dismissal has nothing to show.
  Future<bool> show();
}

/// Every non-web build, and the fallback when interop is unavailable.
class NoInstallPrompt extends InstallPrompt {
  const NoInstallPrompt();

  @override
  InstallOffer get offer => InstallOffer.none;

  @override
  Future<bool> show() async => false;
}
