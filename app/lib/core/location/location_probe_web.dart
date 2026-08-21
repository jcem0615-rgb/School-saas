import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'location_probe.dart';

/// The browser's Geolocation API.
///
/// Only reached through the conditional export in
/// `location_probe_factory.dart`, so nothing here is compiled into a
/// non-web build.
class BrowserLocationProbe implements LocationProbe {
  const BrowserLocationProbe();

  @override
  Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final geolocation = web.window.navigator.geolocation;

    final completer = Completer<LocationResult>();
    // One completer, three ways to finish -- success, browser error, our
    // own deadline -- so every path guards against completing twice.
    void finish(LocationResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    // Our own deadline as well as the browser's. Some browsers keep a
    // request open well past `timeoutMs` while they wait on a hardware
    // fix, and an emergency alert cannot sit behind that.
    final deadline = Timer(timeout, () {
      finish(const LocationResult.failed(LocationFailure.timeout));
    });

    try {
      geolocation.getCurrentPosition(
        (web.GeolocationPosition position) {
          finish(LocationResult.found(LocationFix(
            latitude: position.coords.latitude.toDouble(),
            longitude: position.coords.longitude.toDouble(),
            accuracyMeters: position.coords.accuracy.toDouble(),
            capturedAt: DateTime.now(),
          )));
        }.toJS,
        (web.GeolocationPositionError error) {
          // 1 = PERMISSION_DENIED, 2 = POSITION_UNAVAILABLE, 3 = TIMEOUT.
          finish(LocationResult.failed(switch (error.code) {
            1 => LocationFailure.permissionDenied,
            3 => LocationFailure.timeout,
            _ => LocationFailure.unavailable,
          }));
        }.toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: timeout.inMilliseconds,
          // A fix from the last half minute is fine and returns instantly.
          // Someone who has just pressed an emergency button has not moved
          // far, and waiting for a fresh satellite lock costs seconds that
          // matter more than the metres it would buy.
          maximumAge: 30000,
        ),
      );
    } catch (_) {
      // Geolocation is unavailable in insecure contexts and in some
      // embedded webviews, where touching it throws rather than calling
      // the error callback.
      finish(const LocationResult.failed(LocationFailure.unsupported));
    }

    final result = await completer.future;
    deadline.cancel();
    return result;
  }
}

LocationProbe createLocationProbe() => const BrowserLocationProbe();
