import 'dart:js_interop';
// For `has`, to feature-detect `onChange` on the page's bridge: during a
// rollout the browser can still be holding the previous index.html, and
// calling a method that is not there throws.
import 'dart:js_interop_unsafe';

import 'install_prompt.dart';

/// The object `web/index.html` installs on `window`. Null when the page
/// predates this, which keeps an older deployed index.html from throwing
/// on every build of the screen.
@JS('logicClassInstall')
external _InstallBridge? get _installBridge;

/// The browser's install flow, driven from `web/index.html`.
///
/// The page captures `beforeinstallprompt` and holds the event, because
/// it fires once, early, and is gone if nothing calls
/// `preventDefault()` on it. Dart asks the page what it is holding
/// rather than listening itself: by the time Flutter has booted, the
/// event has usually already come and gone.
///
/// Only reached through the conditional export in
/// `install_prompt_factory.dart`, so nothing here is compiled into a
/// non-web build.
class BrowserInstallPrompt extends InstallPrompt {
  const BrowserInstallPrompt();

  @override
  InstallOffer get offer {
    final bridge = _bridge;
    if (bridge == null) return InstallOffer.none;
    return switch (bridge.offer().toDart) {
      'prompt' => InstallOffer.prompt,
      'instructions' => InstallOffer.instructions,
      _ => InstallOffer.none,
    };
  }

  @override
  Future<bool> show() async {
    final bridge = _bridge;
    if (bridge == null) return false;
    final accepted = await bridge.show().toDart;
    return accepted.toDart;
  }

  @override
  void Function() listen(void Function() onChange) {
    final bridge = _bridge;
    // An older deployed index.html has the bridge but not onChange. The
    // button still works there -- it just falls back to being right
    // whenever something else rebuilds it.
    if (bridge == null || !(bridge as JSObject).has('onChange')) return () {};
    final stop = bridge.onChange(onChange.toJS);
    return () => stop.callAsFunction();
  }

  _InstallBridge? get _bridge => _installBridge;
}

@JS()
extension type _InstallBridge._(JSObject _) implements JSObject {
  external JSString offer();
  external JSPromise<JSBoolean> show();

  /// Returns the function that stops listening.
  external JSFunction onChange(JSFunction callback);
}

InstallPrompt createInstallPrompt() => const BrowserInstallPrompt();
