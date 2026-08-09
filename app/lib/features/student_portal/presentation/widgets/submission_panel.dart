import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/coursework_submission.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../controllers/student_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// Where a student actually does the work: writes an answer, attaches a
/// file, and hands it in.
///
/// Shown only for gradable coursework. A lesson is material to read, and
/// putting a Submit button under one would invite students to hand in
/// nothing against it and believe they had finished something.
class SubmissionPanel extends ConsumerStatefulWidget {
  final CourseworkItem item;
  final StudentSummary student;

  const SubmissionPanel({super.key, required this.item, required this.student});

  @override
  ConsumerState<SubmissionPanel> createState() => _SubmissionPanelState();
}

class _SubmissionPanelState extends ConsumerState<SubmissionPanel> {
  final _answerController = TextEditingController();

  /// Set once from whatever was already handed in, so opening the screen
  /// to revise shows the previous answer rather than a blank box that
  /// looks like the work was lost.
  bool _prefilled = false;
  bool _editing = false;
  bool _uploading = false;
  bool _submitting = false;
  String? _attachmentUrl;
  String? _attachmentName;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _startEditing(CourseworkSubmission? existing) {
    setState(() {
      _editing = true;
      _answerController.text = existing?.answer ?? '';
      _attachmentUrl = existing?.attachmentUrl;
      _attachmentName = existing?.attachmentName;
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      // Matches storage.rules, which only accepts images and PDFs.
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploading = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.coursework,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: file.extension == 'pdf' ? 'application/pdf' : 'image/${file.extension}',
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    switch (result) {
      case Success<UploadedFile>(:final value):
        setState(() {
          _attachmentUrl = value.url;
          _attachmentName = value.fileName;
        });
      case Error<UploadedFile>(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _submit(CourseworkSubmission? existing) async {
    setState(() => _submitting = true);
    final ok = await ref.read(studentActionControllerProvider.notifier).submitCoursework(
          submissionId: existing?.id,
          item: widget.item,
          studentId: widget.student.id,
          studentName: widget.student.fullName,
          section: widget.student.section,
          answer: _answerController.text,
          attachmentUrl: _attachmentUrl,
          attachmentName: _attachmentName,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (ok) _editing = false;
    });
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(existing == null ? 'Handed in.' : 'Your answer was updated.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen(studentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    final submissionsAsync = ref.watch(mySubmissionsProvider(widget.student.id));
    final existing = submissionsAsync.valueOrNull
        ?.where((s) => s.courseworkId == widget.item.id)
        .firstOrNull;

    // Prefill once, and only after the stream has actually delivered --
    // doing it on the first (empty) frame would blank an answer the
    // student had already written.
    if (!_prefilled && submissionsAsync.hasValue) {
      _prefilled = true;
      if (existing == null) _editing = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Text('Your work', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (submissionsAsync.isLoading && !submissionsAsync.hasValue)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_editing)
          _buildEditor(theme, existing)
        else
          _buildSubmitted(theme, existing!),
      ],
    );
  }

  Widget _buildEditor(ThemeData theme, CourseworkSubmission? existing) {
    final overdue = widget.item.dueDate != null &&
        widget.item.dueDate!.isBefore(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overdue)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              // Late work is still accepted -- refusing it would just mean
              // the teacher never sees it -- but nobody should hand it in
              // believing it was on time.
              'The due date has passed. You can still hand this in, and '
              'your teacher will see that it was late.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        TextField(
          controller: _answerController,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Your answer',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickFile,
          icon: _uploading
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.attach_file),
          label: Text(_uploading ? 'Uploading…' : 'Attach a file (optional)'),
        ),
        if (_attachmentName != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(_attachmentName!, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _attachmentUrl = null;
                _attachmentName = null;
              }),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _submitting || _uploading ? null : () => _submit(existing),
          icon: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(existing == null ? 'Hand in' : 'Replace my answer'),
        ),
        if (existing != null)
          TextButton(
            onPressed: _submitting ? null : () => setState(() => _editing = false),
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  Widget _buildSubmitted(ThemeData theme, CourseworkSubmission submission) {
    final late = submission.isLateFor(widget.item);

    return Card(
      color: late ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(late ? Icons.schedule : Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    late ? 'Handed in late' : 'Handed in',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _dateFormat.format(submission.submittedAt) +
                  (submission.wasRevised
                      ? ' · revised ${_dateFormat.format(submission.updatedAt!)}'
                      : ''),
              style: theme.textTheme.bodySmall,
            ),
            if (submission.answer.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(submission.answer),
            ],
            if (submission.hasAttachment)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(submission.attachmentName ?? 'Attached file'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.parse(submission.attachmentUrl!);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Could not open the file.')));
                  }
                },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _startEditing(submission),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Change my answer'),
            ),
          ],
        ),
      ),
    );
  }
}
