import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/coursework_submission.dart';
import '../controllers/faculty_controller.dart';
import 'submissions_screen.dart';
import '../../../../core/widgets/field_tile.dart';

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
                    // Delivery only when it is Online. Nearly everything
                    // is face-to-face, so printing it on every row spent
                    // a phone-width line restating the default -- the
                    // same reason the Draft chip only appears on drafts.
                    '${item.type.displayLabel}'
                    '${item.delivery == CourseworkDelivery.online ? ' · Online' : ''}'
                    ' · ${item.subject} - ${item.section}'
                    '${item.dueDate != null ? ' · Due ${_dateFormat.format(item.dueDate!)}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!item.published)
                        const Chip(label: Text('Draft'), visualDensity: VisualDensity.compact),
                      // Only gradable work is handed in, so only gradable
                      // work has anything to look at here.
                      if (item.acceptsSubmissions)
                        IconButton(
                          icon: const Icon(Icons.assignment_turned_in_outlined),
                          tooltip: 'Submissions',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SubmissionsScreen(item: item)),
                          ),
                        ),
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
    CourseworkDelivery delivery = existing?.delivery ?? CourseworkDelivery.faceToFace;
    DateTime? dueDate = existing?.dueDate;
    bool published = existing?.published ?? true;
    String? attachmentUrl = existing?.attachmentUrl;
    String? attachmentName = existing?.attachmentName;
    bool uploading = false;

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
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: CourseworkType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.displayLabel)))
                      .toList(),
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                // Face-to-face or online. Online is the one that changes
                // what the form demands: the student is not in the room,
                // so the file below stops being optional.
                SegmentedButton<CourseworkDelivery>(
                  segments: CourseworkDelivery.values
                      .map((d) => ButtonSegment(
                            value: d,
                            label: Text(d.displayLabel),
                            icon: Icon(d == CourseworkDelivery.online
                                ? Icons.cloud_outlined
                                : Icons.meeting_room_outlined),
                          ))
                      .toList(),
                  selected: {delivery},
                  onSelectionChanged: (s) => setState(() => delivery = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                // Suggested from the teacher's own assignments, so the
                // common case is a tap while an unassigned subject can
                // still be typed.
                Consumer(
                  builder: (context, ref, _) {
                    // Drawn from what this teacher has already set, which is
                    // the closest thing the faculty side has to a subject
                    // list -- teacherAssignments is an Admin-owned collection
                    // the faculty repository does not read.
                    final mine = ref.watch(myCourseworkStreamProvider).valueOrNull ??
                        const <CourseworkItem>[];
                    return Column(
                      children: [
                        ComboField(
                          controller: subjectController,
                          label: 'Subject',
                          suggestions: mine.map((c) => c.subject).toList(),
                        ),
                        const SizedBox(height: 12),
                        ComboField(
                          controller: sectionController,
                          label: 'Section',
                          suggestions: mine.map((c) => c.section).toList(),
                        ),
                      ],
                    );
                  },
                ),
                if (type.isGradable) ...[
                  const SizedBox(height: 12),
                  FieldTile(
                    icon: Icons.event,
                    label: 'Due date',
                    value: dueDate == null ? null : _dateFormat.format(dueDate!),
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
                    decoration: const InputDecoration(labelText: 'Total Points (optional)'),
                  ),
                ],
                const SizedBox(height: 12),
                // Students read this file from the coursework feed, so it
                // is uploaded before the item is saved -- the item stores
                // only the resulting URL.
                Consumer(
                  builder: (context, ref, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading
                            ? null
                            : () async {
                                final picked = await FilePicker.pickFiles(
                                  withData: true,
                                  type: FileType.custom,
                                  // Matches storage.rules, which only
                                  // accepts images and PDFs.
                                  allowedExtensions: const [
                                    'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp',
                                  ],
                                );
                                final file = picked?.files.singleOrNull;
                                if (file?.bytes == null) return;

                                setState(() => uploading = true);
                                final result = await ref.read(uploadRepositoryProvider).upload(
                                      folder: UploadFolder.coursework,
                                      fileName: file!.name,
                                      bytes: file.bytes!,
                                      contentType: file.extension == 'pdf'
                                          ? 'application/pdf'
                                          : 'image/${file.extension}',
                                    );
                                if (!sheetContext.mounted) return;
                                setState(() => uploading = false);
                                switch (result) {
                                  case Success(:final value):
                                    setState(() {
                                      attachmentUrl = value.url;
                                      attachmentName = value.fileName;
                                    });
                                  case Error(:final failure):
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      SnackBar(content: Text(failure.message)),
                                    );
                                }
                              },
                        icon: uploading
                            ? const SizedBox(
                                height: 16, width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.attach_file),
                        label: Text(
                          uploading
                              ? 'Uploading…'
                              : delivery.requiresAttachment
                                  ? 'Attach the file students will open'
                                  : 'Attach file (optional)',
                        ),
                      ),
                      if (delivery.requiresAttachment && attachmentName == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Online coursework needs a file — that is what the '
                            'student opens to take it.',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(sheetContext).colorScheme.error),
                          ),
                        ),
                      if (attachmentName != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(attachmentName!, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              attachmentUrl = null;
                              attachmentName = null;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
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
                            delivery: delivery,
                            title: titleController.text,
                            description: descriptionController.text,
                            subject: subjectController.text,
                            section: sectionController.text,
                            dueDate: dueDate,
                            totalPoints: double.tryParse(pointsController.text),
                            published: published,
                            attachmentUrl: attachmentUrl,
                            attachmentName: attachmentName,
                          )
                        : await notifier.createCourseworkItem(
                            type: type,
                            delivery: delivery,
                            title: titleController.text,
                            description: descriptionController.text,
                            subject: subjectController.text,
                            section: sectionController.text,
                            dueDate: dueDate,
                            totalPoints: double.tryParse(pointsController.text),
                            published: published,
                            attachmentUrl: attachmentUrl,
                            attachmentName: attachmentName,
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
