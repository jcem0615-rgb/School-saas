import '../core/location/location_probe.dart';

/// Demo mode's stand-in for the device's GPS.
///
/// Returns a fixed point on the seeded school's campus rather than asking
/// the browser. Two reasons: a demo should not put a real location
/// permission prompt in front of somebody who is only clicking through the
/// app -- the same rule the push registrar follows -- and the feature is
/// invisible without a fix, so a demo that always reported "location
/// unavailable" would show the empty state and nothing else.
///
/// The coordinates are a real place (Marikina, Metro Manila) so that
/// "Open in Maps" from the alert opens somewhere recognisable rather than
/// the Gulf of Guinea.
class DemoLocationProbe implements LocationProbe {
  const DemoLocationProbe();

  static const _latitude = 14.6507;
  static const _longitude = 121.1029;

  @override
  Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // A beat of delay so the SOS screen's "Getting your location…" state
    // is actually reachable in the demo rather than skipped in one frame.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return LocationResult.found(LocationFix(
      latitude: _latitude,
      longitude: _longitude,
      accuracyMeters: 12,
      capturedAt: DateTime.now(),
    ));
  }
}

/// The other half of the demo: a probe that always refuses.
///
/// Not wired up by default, but kept beside its opposite so the "student
/// declined to share" path can be driven in a test without hand-rolling a
/// fake.
class DecliningLocationProbe implements LocationProbe {
  const DecliningLocationProbe();

  @override
  Future<LocationResult> current({Duration timeout = const Duration(seconds: 8)}) async =>
      const LocationResult.failed(LocationFailure.permissionDenied);
}
