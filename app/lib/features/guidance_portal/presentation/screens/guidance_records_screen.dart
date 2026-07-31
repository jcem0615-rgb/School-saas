import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../domain/entities/guidance_record.dart';
import '../controllers/guidance_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

class GuidanceRecordsScreen extends ConsumerStatefulWidget {
  const GuidanceRecordsScreen({super.key});

  @override
  ConsumerState<GuidanceRecordsScreen> createState() => _GuidanceRecordsScreenState();
}

class _GuidanceRecordsScreenState extends ConsumerState<GuidanceRecordsScreen> {
  final _studentIdController = TextEditingController();
  final _studentNameController = TextEditingController();
  String? _activeStudentId;

  @override
  void dispose() {
    _studentIdController.dispose();
    _studentNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = _activeStudentId != null ? ref.watch(guidanceRecordsProvider(_activeStudentId!)) : null;

    ref.listen(guidanceActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Guidance Records')),
      // Available with or without a student loaded: with one, the note is
      // filed against that student; without, it is a section-level note.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Note'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _studentIdController,
                        decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _studentNameController,
                        decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_studentIdController.text.trim().isEmpty) return;
                      setState(() => _activeStudentId = _studentIdController.text.trim());
                    },
                    child: const Text('Load Records'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: recordsAsync == null
                ? const Center(child: Text('Enter a student ID to view or add guidance records.'))
                : recordsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Failed to load records: $err')),
                    data: (records) {
                      if (records.isEmpty) {
                        return const Center(child: Text('No guidance records for this student yet.'));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final r = records[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Chip(label: Text(r.category.displayLabel), visualDensity: VisualDensity.compact),
                                      const Spacer(),
                                      // Shrinkable: category chip, date and
                                      // actions menu together overflow a
                                      // phone-width card otherwise.
                                      Flexible(
                                        child: Text(
                                          _dateFormat.format(r.recordedAt),
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ),
                                      RowActionsMenu(
                                        onEdit: () => _showRecordEditor(context, ref, existing: r),
                                        onDelete: () => _confirmDeleteRecord(context, ref, r),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(r.notes),
                                  const SizedBox(height: 8),
                                  Text('— ${r.recordedByName}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRecord(BuildContext context, WidgetRef ref, GuidanceRecord r) async {
    final ok = await confirmDelete(
      context,
      itemLabel: 'guidance record',
      detail: r.studentId == null
          ? '${r.category.displayLabel} note for ${r.section}'
          : '${r.category.displayLabel} note for ${r.studentName}',
    );
    if (!ok) return;
    await ref.read(guidanceActionControllerProvider.notifier).deleteGuidanceRecord(r.id);
  }

  /// Edit only touches category and notes. The student a note belongs to
  /// is fixed: firestore.rules rejects any update that changes studentId.
  Future<void> _showRecordEditor(
    BuildContext context,
    WidgetRef ref, {
    required GuidanceRecord existing,
  }) async {
    final notesController = TextEditingController(text: existing.notes);
    GuidanceCategory category = existing.category;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Edit Guidance Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  existing.studentId == null
                      ? 'Section-level note · ${existing.section}'
                      : 'Student: ${existing.studentName} · ${existing.section}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GuidanceCategory>(
                  isExpanded: true,
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: GuidanceCategory.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.displayLabel)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final success = await ref
                    .read(guidanceActionControllerProvider.notifier)
                    .updateGuidanceRecord(
                      recordId: existing.id,
                      category: category,
                      notes: notesController.text,
                    );
                if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final notesController = TextEditingController();
    final sectionController = TextEditingController();
    // Sections seen on the records already loaded. Guidance has no student
    // list of its own, and adding one just to populate a suggestion list
    // would widen what this portal reads for a convenience.
    final sectionSuggestions = (_activeStudentId == null
            ? const <GuidanceRecord>[]
            : ref.read(guidanceRecordsProvider(_activeStudentId!)).valueOrNull ??
                const <GuidanceRecord>[])
        .map((r) => r.section)
        .toList();
    GuidanceCategory category = GuidanceCategory.behavioral;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add Guidance Note'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<GuidanceCategory>(
                  isExpanded: true,
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: GuidanceCategory.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.displayLabel)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                ComboField(
                  controller: sectionController,
                  label: 'Section',
                  suggestions: sectionSuggestions,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Text(
                  _activeStudentId == null || _activeStudentId!.isEmpty
                      ? 'No student loaded — this will be filed as a section-level note.'
                      : 'Filed against $_activeStudentId in this section.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final success = await ref.read(guidanceActionControllerProvider.notifier).createGuidanceRecord(
                      // Blank student = a note about the whole section.
                      // The usecase normalises empty to null, which is what
                      // firestore.rules keys its scoping on.
                      studentId: _activeStudentId,
                      studentName: _studentNameController.text.trim().isEmpty
                          ? _activeStudentId
                          : _studentNameController.text,
                      section: sectionController.text,
                      category: category,
                      notes: notesController.text,
                    );
                if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
