/// Asking the device where it is.
///
/// A port rather than a direct browser/plugin call, for the same reason as
/// PushRegistrar: demo mode must not put a real permission prompt in front
/// of somebody who is only clicking through the app, tests must not depend
/// on a device that has no GPS, and the app is web-only today but the
/// pubspec targets phones next.
abstract class LocationProbe {
  /// Best effort, always bounded.
  ///
  /// Never throws and never waits longer than [timeout]: the caller is an
  /// emergency alert, and a fix that arrives after help was delayed is
  /// worse than no fix. Failure comes back as a [LocationResult] carrying
  /// a reason, not as an exception.
  Future<LocationResult> current({Duration timeout});
}

/// Where the device says it is, and how sure it is.
class LocationFix {
  final double latitude;
  final double longitude;

  /// Radius in metres the real position is expected to lie within. A fix
  /// accurate to 2km and one accurate to 5m look identical without it,
  /// and staff deciding whether to search a room or a barangay need to
  /// know which they have.
  final double? accuracyMeters;

  final DateTime capturedAt;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
  });
}

/// Why there is no fix.
///
/// Recorded on the alert rather than dropped, because "the student chose
/// not to share their location" and "the app never asked" look the same
/// to staff otherwise -- and only one of them is a reason to stop waiting
/// and start searching.
enum LocationFailure {
  /// The person declined the permission prompt, or the browser has it
  /// blocked for this site.
  permissionDenied,

  /// Asked, but the device could not produce a position -- indoors with
  /// no GPS, location services switched off.
  unavailable,

  /// Did not answer in time. Common indoors on a cold start.
  timeout,

  /// This build cannot ask at all.
  unsupported;

  /// Phrased for staff reading an alert, not for a log.
  String get staffExplanation => switch (this) {
        LocationFailure.permissionDenied =>
          'The student did not share their location.',
        LocationFailure.unavailable =>
          'Their device could not get a location.',
        LocationFailure.timeout =>
          'Their location did not arrive in time.',
        LocationFailure.unsupported =>
          'Location sharing is not available on their device.',
      };

  static LocationFailure? fromValue(String? value) => switch (value) {
        'permission_denied' => LocationFailure.permissionDenied,
        'unavailable' => LocationFailure.unavailable,
        'timeout' => LocationFailure.timeout,
        'unsupported' => LocationFailure.unsupported,
        _ => null,
      };

  String get value => switch (this) {
        LocationFailure.permissionDenied => 'permission_denied',
        LocationFailure.unavailable => 'unavailable',
        LocationFailure.timeout => 'timeout',
        LocationFailure.unsupported => 'unsupported',
      };
}

/// Exactly one of [fix] or [failure] is set.
class LocationResult {
  final LocationFix? fix;
  final LocationFailure? failure;

  const LocationResult.found(LocationFix this.fix) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : fix = null;
}

/// Used where asking is not possible or not wanted: non-web builds until
/// a plugin is added, and widget tests.
class UnsupportedLocationProbe implements LocationProbe {
  const UnsupportedLocationProbe();

  @override
  Future<LocationResult> current({Duration timeout = const Duration(seconds: 8)}) async =>
      const LocationResult.failed(LocationFailure.unsupported);
}
