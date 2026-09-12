/// Picks the install prompt for the platform this build targets.
///
/// A conditional export rather than a runtime `kIsWeb` check, so
/// `package:web` is never compiled into a phone build -- the same shape
/// as `location_probe_factory.dart`.
library;

export 'install_prompt.dart';
export 'install_prompt_stub.dart'
    if (dart.library.js_interop) 'install_prompt_web.dart';
