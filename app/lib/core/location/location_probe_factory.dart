/// Picks the probe for the platform this build targets.
///
/// Three-way: the browser has a Geolocation API and needs no plugin, phones
/// need geolocator, and anything else (desktop, tests) gets the honest
/// "not available" stub. Conditional exports rather than a runtime switch,
/// so `package:web` is never compiled into a phone build and geolocator is
/// never compiled into the web one.
library;

export 'location_probe_stub.dart'
    if (dart.library.js_interop) 'location_probe_web.dart'
    if (dart.library.io) 'location_probe_mobile.dart';
