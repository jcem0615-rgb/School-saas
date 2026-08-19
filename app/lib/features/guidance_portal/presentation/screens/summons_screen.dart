import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/summons.dart';
import '../controllers/guidance_controller.dart';

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
        onPressed: () => _showCreateSheet(context, ref),
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
                  trailing: s.status == SummonsStatus.pending
                      ? PopupMenuButton<SummonsStatus>(
                          onSelected: (status) => ref
                              .read(guidanceActionControllerProvider.notifier)
                              .updateSummonsStatus(summonsId: s.id, status: status),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: SummonsStatus.completed, child: Text('Mark Completed')),
                            PopupMenuItem(value: SummonsStatus.cancelled, child: Text('Cancel')),
                          ],
                        )
                      : Chip(label: Text(s.status.displayLabel), visualDensity: VisualDensity.compact),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final studentIdController = TextEditingController();
    final studentNameController = TextEditingController();
    final reasonController = TextEditingController();
    DateTime scheduledDate = DateTime.now().add(const Duration(days: 1));

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
                Text('New Summons', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: studentIdController,
                  decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: studentNameController,
                  decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Scheduled: ${_dateFormat.format(scheduledDate)}'),
                  trailing: const Icon(Icons.event),
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
                    final success = await ref.read(guidanceActionControllerProvider.notifier).createSummons(
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
