/// Picks the way into a video class for the platform this build targets.
///
/// A conditional export rather than a runtime `kIsWeb` check, the same
/// shape as `install_prompt_factory.dart` and `location_probe_factory.dart`:
/// the web implementation touches `package:web` and `dart:ui_web`, and a
/// phone build must never compile either.
library;

export 'meeting_room.dart';
export 'meeting_launcher_stub.dart'
    if (dart.library.js_interop) 'meeting_launcher_web.dart';
