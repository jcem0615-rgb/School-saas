import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/coursework_item.dart';
import '../controllers/faculty_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class CourseworkListScreen extends ConsumerWidget {
  const CourseworkListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(myCourseworkStreamProvider);

    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Coursework')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load coursework: $err')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No coursework created yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(child: Text(item.type.displayLabel[0])),
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.type.displayLabel} · ${item.subject} - ${item.section}'
                    '${item.dueDate != null ? ' · Due ${_dateFormat.format(item.dueDate!)}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!item.published)
                        const Chip(label: Text('Draft'), visualDensity: VisualDensity.compact),
                      RowActionsMenu(
                        onEdit: () => _showEditor(context, ref, existing: item),
                        onDelete: () => _confirmDelete(context, ref, item),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CourseworkItem item) async {
    final ok = await confirmDelete(
      context,
      itemLabel: item.type.displayLabel.toLowerCase(),
      detail: item.title,
    );
    if (!ok) return;
    await ref.read(facultyActionControllerProvider.notifier).deleteCourseworkItem(item.id);
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, {CourseworkItem? existing}) async {
    final isEdit = existing != null;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final subjectController = TextEditingController(text: existing?.subject ?? '');
    final sectionController = TextEditingController(text: existing?.section ?? '');
    final pointsController =
        TextEditingController(text: existing?.totalPoints?.toString() ?? '');
    CourseworkType type = existing?.type ?? CourseworkType.lesson;
    DateTime? dueDate = existing?.dueDate;
    bool published = existing?.published ?? true;

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
                Text('New Coursework', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<CourseworkType>(
                  isExpanded: true,
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: CourseworkType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.displayLabel)))
                      .toList(),
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sectionController,
                  decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
                ),
                if (type.isGradable) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(dueDate == null ? 'Pick due date' : _dateFormat.format(dueDate!)),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => dueDate = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total Points (optional)', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: published,
                  onChanged: (v) => setState(() => published = v),
                  title: const Text('Publish now'),
                  subtitle: const Text('Off saves as a draft, visible only to staff.'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final notifier = ref.read(facultyActionControllerProvider.notifier);
                    final success = isEdit
                        ? await notifier.updateCourseworkItem(
                            itemId: existing.id,
                            type: type,
                            title: titleController.text,
                            description: descriptionController.text,
                            subject: subjectController.text,
                            section: sectionController.text,
                            dueDate: dueDate,
                            totalPoints: double.tryParse(pointsController.text),
                            published: published,
                          )
                        : await notifier.createCourseworkItem(
                            type: type,
                            title: titleController.text,
                            description: descriptionController.text,
                            subject: subjectController.text,
                            section: sectionController.text,
                            dueDate: dueDate,
                            totalPoints: double.tryParse(pointsController.text),
                            published: published,
                          );
                    if (success && sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: Text(isEdit ? 'Save Changes' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
