import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/emergency_alert.dart';

/// Where the student was, on a staff member's alert card.
///
/// Deliberately not a rendered map. An embedded map needs a key, a tile
/// budget and a network round trip on a screen whose whole job is to work
/// when things are going wrong; a coordinate and a button that hands it to
/// whatever map app the responder already has on their phone does the same
/// job with none of that. It also degrades honestly -- if the button
/// cannot open anything, the numbers are still on screen to read out over
/// a radio or a phone.
class AlertLocation extends StatelessWidget {
  final EmergencyAlert alert;
  const AlertLocation({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!alert.hasLocation) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_off_outlined,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // Says which kind of "no location" this is. "The student did
              // not share their location" and "nobody ever asked" lead to
              // different next moves, and staff should not have to guess
              // which one they are looking at.
              alert.locationFailure?.staffExplanation ??
                  'No location was recorded with this alert.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final latitude = alert.latitude!;
    final longitude = alert.longitude!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.my_location, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Five decimal places is about a metre. More digits
                    // would imply a precision the device does not have.
                    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _accuracyLabel(alert.locationAccuracyMeters),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _openInMaps(context, latitude, longitude),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open in Maps'),
            ),
          ],
        ),
      ],
    );
  }

  /// Accuracy in the terms a responder actually needs: is this a room or a
  /// neighbourhood?
  static String _accuracyLabel(double? accuracyMeters) {
    if (accuracyMeters == null) {
      return 'Where they pressed the button · accuracy unknown';
    }
    if (accuracyMeters >= 1000) {
      final km = (accuracyMeters / 1000).toStringAsFixed(1);
      return 'Where they pressed the button · only accurate to about $km km';
    }
    return 'Where they pressed the button · accurate to about '
        '${accuracyMeters.round()} m';
  }

  Future<void> _openInMaps(
      BuildContext context, double latitude, double longitude) async {
    // The universal Google Maps URL rather than a geo: URI: geo: opens
    // nothing on desktop web, which is where a school office is most
    // likely to be reading this.
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Could not open a map. Coordinates: '
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'),
        ));
    }
  }
}
