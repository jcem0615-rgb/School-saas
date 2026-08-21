import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_probe.dart';
import 'location_probe_factory.dart';

/// Overridden in demo mode (see demo_overrides.dart) and in tests.
final locationProbeProvider = Provider<LocationProbe>((ref) => createLocationProbe());
