import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/checklist_item.dart';
import '../controllers/staff_controller.dart';

String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  late final String _date;

  @override
  void initState() {
    super.initState();
    _date = _todayKey();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(myChecklistProvider(_date));

    ref.listen(staffActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text('Checklist · ${DateFormat.yMMMd().format(DateTime.now())}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load checklist: $err')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No tasks for today yet.'));
          }
          final completedCount = items.where((i) => i.completed).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: LinearProgressIndicator(value: items.isEmpty ? 0 : completedCount / items.length),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    // CheckboxListTile owns its trailing slot, so the
                    // actions menu goes in a Row alongside it rather than
                    // inside the tile.
                    return Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            value: item.completed,
                            title: Text(
                              item.task,
                              style: item.completed
                                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                                  : null,
                            ),
                            onChanged: (v) =>
                                ref.read(staffActionControllerProvider.notifier).toggleChecklistItem(
                                      itemId: item.id,
                                      completed: v ?? false,
                                    ),
                          ),
                        ),
                        RowActionsMenu(
                          onEdit: () => _showEditDialog(context, ref, item),
                          onDelete: () => _confirmDelete(context, ref, item),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ChecklistItem item) async {
    final ok = await confirmDelete(context, itemLabel: 'task', detail: item.task);
    if (!ok) return;
    await ref.read(staffActionControllerProvider.notifier).deleteChecklistItem(item.id);
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, ChecklistItem item) async {
    final taskController = TextEditingController(text: item.task);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Task'),
        content: TextField(
          controller: taskController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Task'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final success = await ref
                  .read(staffActionControllerProvider.notifier)
                  .updateChecklistItem(itemId: item.id, task: taskController.text);
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final taskController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Task'),
        content: TextField(
          controller: taskController,
          decoration: const InputDecoration(labelText: 'Task'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final success = await ref
                  .read(staffActionControllerProvider.notifier)
                  .addChecklistItem(task: taskController.text, date: _date);
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
