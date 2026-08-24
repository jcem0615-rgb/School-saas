import 'location_probe.dart';

/// Non-web builds. The pubspec targets phones, but there is no location
/// plugin in it yet -- so rather than guess at one, this says so honestly
/// and the alert records "not available on their device" instead of
/// pretending the student declined.
LocationProbe createLocationProbe() => const UnsupportedLocationProbe();
