import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
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
        onPressed: () => _showEditor(context, ref),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cancelled)
                        const Text('CANCELLED', style: TextStyle(color: Colors.red, fontSize: 11)),
                      RowActionsMenu(
                        onEdit: () => _showEditor(context, ref, existing: m),
                        onDelete: () => _confirmDelete(context, ref, m),
                        // Cancelling and deleting are different intents:
                        // a cancelled meeting stays visible so attendees
                        // know it was called off, a deleted one does not.
                        extraActions: cancelled
                            ? const []
                            : const [
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.cancel_outlined, size: 20),
                                    title: Text('Cancel meeting'),
                                  ),
                                ),
                              ],
                        onExtraAction: (value) {
                          if (value == 'cancel') {
                            ref.read(directorActionControllerProvider.notifier).cancelMeeting(m.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Meeting m) async {
    final ok = await confirmDelete(context, itemLabel: 'meeting', detail: m.title);
    if (!ok) return;
    await ref.read(directorActionControllerProvider.notifier).deleteMeeting(m.id);
  }

  /// One sheet for both scheduling and editing -- see the note on the
  /// announcements editor for why these are not two separate forms.
  Future<void> _showEditor(BuildContext context, WidgetRef ref, {Meeting? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final locationController = TextEditingController(text: existing?.location ?? '');
    DateTime? startTime = existing?.startTime;
    DateTime? endTime = existing?.endTime;
    final selectedRoles = <String>{...?existing?.attendeeRoles};

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
                Text(isEdit ? 'Edit Meeting' : 'Schedule a Meeting',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
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
                    final notifier = ref.read(directorActionControllerProvider.notifier);
                    final success = isEdit
                        ? await notifier.updateMeeting(
                            meetingId: existing.id,
                            title: titleController.text,
                            description: descriptionController.text,
                            startTime: startTime!,
                            endTime: endTime!,
                            location: locationController.text,
                            attendeeRoles: selectedRoles.toList(),
                          )
                        : await notifier.createMeeting(
                            title: titleController.text,
                            description: descriptionController.text,
                            startTime: startTime!,
                            endTime: endTime!,
                            location: locationController.text,
                            attendeeRoles: selectedRoles.toList(),
                          );
                    if (success && sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: Text(isEdit ? 'Save Changes' : 'Schedule Meeting'),
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
