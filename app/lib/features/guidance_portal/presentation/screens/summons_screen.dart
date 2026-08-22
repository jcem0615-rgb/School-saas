import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/summons.dart';
import '../controllers/guidance_controller.dart';
import '../../../../core/widgets/field_tile.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

class SummonsScreen extends ConsumerWidget {
  const SummonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summonsAsync = ref.watch(summonsStreamProvider);

    ref.listen(guidanceActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Student Summons')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Summons'),
      ),
      body: summonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load summons: $err')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No summons issued yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = list[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text(s.studentName),
                  subtitle: Text('${s.reason}\n${_dateFormat.format(s.scheduledDate)}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s.status != SummonsStatus.pending)
                        Chip(label: Text(s.status.displayLabel), visualDensity: VisualDensity.compact),
                      RowActionsMenu(
                        onEdit: () => _showEditor(context, ref, existing: s),
                        onDelete: () => _confirmDelete(context, ref, s),
                        // Status changes stay distinct from deletion: a
                        // completed or cancelled summons is still part of
                        // the student's record, a deleted one is not.
                        extraActions: s.status == SummonsStatus.pending
                            ? const [
                                PopupMenuItem(
                                  value: 'completed',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.check_circle_outline, size: 20),
                                    title: Text('Mark completed'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'cancelled',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.block, size: 20),
                                    title: Text('Cancel summons'),
                                  ),
                                ),
                              ]
                            : const [],
                        onExtraAction: (value) {
                          final status = value == 'completed'
                              ? SummonsStatus.completed
                              : SummonsStatus.cancelled;
                          ref
                              .read(guidanceActionControllerProvider.notifier)
                              .updateSummonsStatus(summonsId: s.id, status: status);
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Summons s) async {
    final ok = await confirmDelete(
      context,
      itemLabel: 'summons',
      detail: '${s.studentName} — ${s.reason}',
    );
    if (!ok) return;
    await ref.read(guidanceActionControllerProvider.notifier).deleteSummons(s.id);
  }

  /// On edit, only reason and schedule are changeable -- the student a
  /// summons is about is fixed, same as guidance records.
  Future<void> _showEditor(BuildContext context, WidgetRef ref, {Summons? existing}) async {
    final isEdit = existing != null;
    final studentIdController = TextEditingController(text: existing?.studentId ?? '');
    final studentNameController = TextEditingController(text: existing?.studentName ?? '');
    final reasonController = TextEditingController(text: existing?.reason ?? '');
    DateTime scheduledDate =
        existing?.scheduledDate ?? DateTime.now().add(const Duration(days: 1));

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
                Text(isEdit ? 'Edit Summons' : 'New Summons',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: studentIdController,
                  readOnly: isEdit,
                  decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: studentNameController,
                  readOnly: isEdit,
                  decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FieldTile(
                  icon: Icons.event,
                  label: 'Scheduled for',
                  value: _dateFormat.format(scheduledDate),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: sheetContext,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                      initialDate: scheduledDate,
                    );
                    if (date == null || !sheetContext.mounted) return;
                    final time = await showTimePicker(
                      context: sheetContext,
                      initialTime: TimeOfDay.fromDateTime(scheduledDate),
                    );
                    if (time == null) return;
                    setState(() => scheduledDate =
                        DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final notifier = ref.read(guidanceActionControllerProvider.notifier);
                    final success = isEdit
                        ? await notifier.updateSummons(
                            summonsId: existing.id,
                            reason: reasonController.text,
                            scheduledDate: scheduledDate,
                          )
                        : await notifier.createSummons(
                            studentId: studentIdController.text,
                            studentName: studentNameController.text,
                            reason: reasonController.text,
                            scheduledDate: scheduledDate,
                          );
                    if (success && sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Issue Summons'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
