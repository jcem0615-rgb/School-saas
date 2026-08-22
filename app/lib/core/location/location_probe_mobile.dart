import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_probe.dart';

/// Android and iOS, via geolocator.
///
/// Only reached through the conditional export in
/// `location_probe_factory.dart`, so geolocator is never pulled into the
/// web build -- the browser has its own Geolocation API and does not need
/// a plugin.
class MobileLocationProbe implements LocationProbe {
  const MobileLocationProbe();

  @override
  Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        // Location switched off device-wide. Deliberately *not* reported
        // as "denied": the student has not refused anything, and telling
        // staff they did would be wrong about the one thing this field
        // exists to get right.
        return const LocationResult.failed(LocationFailure.unavailable);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.permissionDenied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // High accuracy matters here more than battery: the difference
          // between a building and a room is the difference between
          // finding a student quickly and searching for them.
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );

      return LocationResult.found(LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: DateTime.now(),
      ));
    } on TimeoutException {
      return const LocationResult.failed(LocationFailure.timeout);
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationFailure.unavailable);
    } on PermissionDefinitionsNotFoundException {
      // The manifest or Info.plist entry is missing -- a build problem,
      // not something the student did.
      return const LocationResult.failed(LocationFailure.unsupported);
    } catch (_) {
      // LocationProbe promises never to throw, and this is the one call
      // where breaking that promise would leave a student who pressed the
      // emergency button watching a spinner.
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }
}

LocationProbe createLocationProbe() => const MobileLocationProbe();
