import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../controllers/emergency_controller.dart';
import 'emergency_contacts_screen.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// The student's emergency button.
///
/// Two things are true at once and the screen has to hold both: it must
/// be fast, because a student using it is in trouble; and it must not
/// fire by accident, because a false alarm at 2am teaches a parent to
/// ignore the next one. The resolution is one deliberate confirm step
/// with the consequence spelled out -- not a countdown, not a long press
/// somebody has to discover.
///
/// The school's published numbers sit on the same screen. Alerting an
/// adviser is not the same as calling the fire brigade, and a student
/// should not have to remember which screen has which.
class SosScreen extends ConsumerStatefulWidget {
  final StudentSummary student;
  const SosScreen({super.key, required this.student});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _raise() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Send an emergency alert?'),
        content: const Text(
          'This notifies your class adviser and your parents or guardians '
          'straight away, on their phones.\n\n'
          'If you are in immediate danger, call the emergency numbers on '
          'this screen as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send alert'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    final ok = await ref.read(emergencyActionControllerProvider.notifier).raiseAlert(
          studentId: widget.student.id,
          studentName: widget.student.fullName,
          section: widget.student.section,
          message: _messageController.text,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _messageController.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Alert sent. Your adviser and parents have been notified.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = ref.watch(myEmergencyAlertsProvider(widget.student.id)).valueOrNull ?? const [];
    final active = mine.where((a) => a.isActive).toList();

    ref.listen(emergencyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (active.isNotEmpty)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alert sent', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(_dateFormat.format(active.first.raisedAt)),
                    const SizedBox(height: 8),
                    Text(
                      active.first.isAcknowledged
                          ? '${active.first.acknowledgedByName} has seen this and is on the way.'
                          : 'Waiting for someone to acknowledge it.',
                    ),
                  ],
                ),
              ),
            ),
          if (active.isNotEmpty) const SizedBox(height: 16),
          Text(
            'What is happening? (optional)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Where you are, and what kind of help you need',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                textStyle: theme.textTheme.titleLarge,
              ),
              onPressed: _sending ? null : _raise,
              icon: _sending
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.emergency_share, size: 32),
              label: Text(_sending ? 'Sending…' : 'Send emergency alert'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Goes to your class adviser and your parents or guardians.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const Divider(height: 40),
          Text('Call for help', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'For fire, police or medical help, call these directly — an '
            'alert to your adviser is not a substitute.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          const _InlineEmergencyNumbers(),
        ],
      ),
    );
  }
}

/// The published numbers, inline. A student in trouble should not have to
/// back out of this screen to find them.
class _InlineEmergencyNumbers extends ConsumerWidget {
  const _InlineEmergencyNumbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(emergencyContactsProvider).valueOrNull ?? const [];
    if (contacts.isEmpty) {
      return const Text('Your school has not published any emergency numbers yet.');
    }
    return Column(
      children: [
        for (final c in contacts.take(4))
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.local_phone_outlined),
              title: Text(c.label),
              subtitle: Text(c.phone),
              trailing: const Icon(Icons.call),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
              ),
            ),
          ),
        if (contacts.length > 4)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
            ),
            child: Text('See all ${contacts.length} numbers'),
          ),
      ],
    );
  }
}
