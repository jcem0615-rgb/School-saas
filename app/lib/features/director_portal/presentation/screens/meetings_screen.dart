import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/meeting.dart';
import '../controllers/director_controller.dart';

final _dateTimeFormat = DateFormat.yMMMd().add_jm();

const _attendeeRoleOptions = ['director', 'admin', 'registrar', 'faculty', 'staff', 'guidance'];

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingsAsync = ref.watch(meetingsStreamProvider);

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Meeting Scheduler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
      body: meetingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load meetings: $err')),
        data: (meetings) {
          if (meetings.isEmpty) {
            return const Center(child: Text('No meetings scheduled.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = meetings[index];
              final cancelled = m.status == MeetingStatus.cancelled;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text(
                    m.title,
                    style: cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                  ),
                  subtitle: Text(
                    '${_dateTimeFormat.format(m.startTime)}'
                    '${m.location != null ? ' · ${m.location}' : ''}\n'
                    'Attendees: ${m.attendeeRoles.join(", ")}',
                  ),
                  isThreeLine: true,
                  trailing: cancelled
                      ? const Text('CANCELLED', style: TextStyle(color: Colors.red, fontSize: 11))
                      : IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          tooltip: 'Cancel meeting',
                          onPressed: () => ref.read(directorActionControllerProvider.notifier).cancelMeeting(m.id),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    DateTime? startTime;
    DateTime? endTime;
    final selectedRoles = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Schedule a Meeting', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Location (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(startTime == null ? 'Pick start time' : _dateTimeFormat.format(startTime!)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final picked = await _pickDateTime(sheetContext);
                    if (picked != null) setState(() => startTime = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(endTime == null ? 'Pick end time' : _dateTimeFormat.format(endTime!)),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: () async {
                    final picked = await _pickDateTime(sheetContext);
                    if (picked != null) setState(() => endTime = picked);
                  },
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text('Attendees', style: Theme.of(sheetContext).textTheme.labelLarge)),
                Wrap(
                  spacing: 8,
                  children: _attendeeRoleOptions.map((role) {
                    final selected = selectedRoles.contains(role);
                    return FilterChip(
                      label: Text(role),
                      selected: selected,
                      onSelected: (v) => setState(() => v ? selectedRoles.add(role) : selectedRoles.remove(role)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (startTime == null || endTime == null) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Please select both a start and end time.')),
                      );
                      return;
                    }
                    final success = await ref.read(directorActionControllerProvider.notifier).createMeeting(
                          title: titleController.text,
                          description: descriptionController.text,
                          startTime: startTime!,
                          endTime: endTime!,
                          location: locationController.text,
                          attendeeRoles: selectedRoles.toList(),
                        );
                    if (success && sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Schedule Meeting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
