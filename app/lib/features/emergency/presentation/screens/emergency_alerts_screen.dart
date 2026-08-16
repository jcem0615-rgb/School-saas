import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/emergency_alert.dart';
import '../controllers/emergency_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// Live emergency alerts, for staff.
///
/// This exists because push cannot be relied on. Notification permission
/// gets declined, a service worker fails to register, the Firebase
/// project is not configured yet -- and none of that should mean an alert
/// goes unseen. The list is the dependable channel; the push is the fast
/// one.
class EmergencyAlertsScreen extends ConsumerWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(emergencyAlertsProvider);

    ref.listen(emergencyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Alerts')),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load alerts: $err')),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No emergency alerts have been raised.'),
              ),
            );
          }
          final active = alerts.where((a) => a.isActive).toList();
          final closed = alerts.where((a) => !a.isActive).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                Text('Needs attention', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...active.map((a) => _AlertCard(alert: a, ref: ref)),
                const SizedBox(height: 24),
              ],
              if (closed.isNotEmpty) ...[
                Text('Resolved', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...closed.map((a) => _AlertCard(alert: a, ref: ref)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final EmergencyAlert alert;
  final WidgetRef ref;

  const _AlertCard({required this.alert, required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: alert.isActive
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
                Icon(alert.isActive ? Icons.emergency_share : Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alert.studentName, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            Text('${alert.section} · ${_dateFormat.format(alert.raisedAt)}',
                style: theme.textTheme.bodySmall),
            if (alert.message != null && alert.message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(alert.message!),
            ],
            if (alert.isAcknowledged)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Acknowledged by ${alert.acknowledgedByName}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (alert.isResolved && alert.resolutionNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Resolved: ${alert.resolutionNote}',
                    style: theme.textTheme.bodySmall),
              ),
            if (alert.isActive) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!alert.isAcknowledged)
                    TextButton(
                      // Acknowledging is separate from resolving on
                      // purpose: "I have seen this and I am going" is the
                      // thing the student needs to know first, and it
                      // costs one tap rather than a form.
                      onPressed: () => ref
                          .read(emergencyActionControllerProvider.notifier)
                          .acknowledgeAlert(alert.id),
                      child: const Text("I'm on it"),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _resolve(context),
                    child: const Text('Resolve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(BuildContext context) async {
    final noteController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Resolve ${alert.studentName}\'s alert'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What happened',
            hintText: 'Brought to the clinic, parents called.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(emergencyActionControllerProvider.notifier)
        .resolveAlert(alertId: alert.id, note: noteController.text);
  }
}
