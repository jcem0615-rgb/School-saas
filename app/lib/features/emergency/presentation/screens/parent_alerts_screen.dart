import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/emergency_alert.dart';
import '../controllers/emergency_controller.dart';
import '../widgets/alert_location.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// What a parent sees when their child presses the button.
///
/// The push notification already goes out — `onEmergencyAlertCreated`
/// resolves the linked parents server-side and sends to their devices.
/// This screen exists for the same reason the staff list does: push
/// cannot be relied on. Notification permission gets declined, a service
/// worker fails to register, a phone is on silent in a bag. A parent who
/// hears nothing and opens the app anyway has to be able to find out.
///
/// It answers the three questions a parent actually has, in the order
/// they have them: is this still happening, where were they, and has
/// anybody from the school picked it up.
class ParentAlertsScreen extends ConsumerWidget {
  const ParentAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alerts = ref.watch(childrenEmergencyAlertsProvider);
    final active = alerts.where((a) => a.isActive).toList();
    final past = alerts.where((a) => !a.isActive).toList();
    final contacts = ref.watch(emergencyContactsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Alerts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (active.isNotEmpty) ...[
            Text('Happening now', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...active.map((a) => _ParentAlertCard(alert: a)),
            const SizedBox(height: 24),
          ],
          // The school's own numbers, on this screen rather than one tap
          // away. A parent who has just read that their child pressed the
          // button is going to call somebody, and making them navigate to
          // find the number is the wrong thing to do to them.
          if (contacts.isNotEmpty) ...[
            Text('Call the school', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...contacts.map(
              (c) => Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(c.label),
                  subtitle: Text(c.phone),
                  trailing: const Icon(Icons.call),
                  onTap: () => _call(context, c.phone),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (past.isNotEmpty) ...[
            Text('Earlier', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...past.map((a) => _ParentAlertCard(alert: a)),
          ],
          if (alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    'No emergency alerts.',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'If your child presses the emergency button in their '
                    'app, it appears here and your phone is notified.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not dial $phone.')));
    }
  }
}

/// A parent's view of one alert.
///
/// Deliberately not the staff card. A parent cannot acknowledge or
/// resolve anything, so those buttons are absent — but the acknowledged
/// state is the single most reassuring fact on the screen, so it is
/// stated in words rather than left as a colour a parent has no key to.
class _ParentAlertCard extends StatelessWidget {
  final EmergencyAlert alert;

  const _ParentAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = alert.isActive;

    final String status;
    if (alert.isResolved) {
      status = alert.resolutionNote?.trim().isNotEmpty == true
          ? 'Resolved by the school — ${alert.resolutionNote!.trim()}'
          : 'Resolved by the school.';
    } else if (alert.isAcknowledged) {
      status = '${alert.acknowledgedByName} from the school is on the way.';
    } else {
      // Said plainly. A parent reading "raised" would not know whether
      // that means anybody has seen it.
      status = 'Sent to the school. Nobody has picked it up yet.';
    }

    return Card(
      color: active
          ? (alert.isAcknowledged
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.errorContainer)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(active ? Icons.emergency_share : Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${alert.studentName} pressed the emergency button',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_dateFormat.format(alert.raisedAt), style: theme.textTheme.bodySmall),
            if (alert.message != null && alert.message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('"${alert.message!}"'),
            ],
            const SizedBox(height: 8),
            AlertLocation(alert: alert),
            const SizedBox(height: 8),
            Text(status, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
