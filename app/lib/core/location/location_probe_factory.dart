/// Picks the probe for the platform this build targets.
library;

export 'location_probe_stub.dart'
    if (dart.library.js_interop) 'location_probe_web.dart';
