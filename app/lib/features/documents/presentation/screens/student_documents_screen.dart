import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data_transfer/open_attachment.dart';
import '../../domain/entities/student_document.dart';
import '../controllers/documents_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// A student's folder.
///
/// The screen answers the two questions a registrar's office is actually
/// asked about a child's papers: what do we hold, and what did we give
/// out. The second is why issued copies sit in the same list as received
/// ones rather than on a separate tab -- they are the same folder, and a
/// school looking for "the Form 137 we released in March" should not have
/// to know which half of the product filed it.
///
/// Read-only for the family. A parent sees what the school holds on their
/// child, which is the phone call this saves; they cannot add to it or
/// take anything out, and firestore.rules says so independently of this
/// flag.
class StudentDocumentsScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String studentName;
  final bool readOnly;

  const StudentDocumentsScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.readOnly = false,
  });

  @override
  ConsumerState<StudentDocumentsScreen> createState() => _StudentDocumentsScreenState();
}

class _StudentDocumentsScreenState extends ConsumerState<StudentDocumentsScreen> {
  /// Archived papers are hidden until asked for. They are history, and a
  /// folder that opens on everything it ever held buries what it holds
  /// now -- which is the question being asked nine times out of ten.
  bool _showArchived = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fileDocument() async {
    final choice = await showModalBottomSheet<_FilingChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FileDocumentSheet(),
    );
    if (choice == null || !mounted) return;

    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null || !mounted) return;

    final ok = await ref.read(documentsActionControllerProvider.notifier).fileScannedDocument(
          studentId: widget.studentId,
          studentName: widget.studentName,
          kind: choice.kind,
          title: choice.title,
          note: choice.note,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: _contentTypeFor(file.extension),
        );
    if (!mounted) return;
    if (ok) _say('Filed.');
  }

  /// From the extension, because `PlatformFile` does not carry a MIME type
  /// on every platform. storage.rules only accepts a PDF or an image, so
  /// anything the picker let through that is neither is named honestly and
  /// refused by the controller rather than guessed at.
  static String _contentTypeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _archive(StudentDocument document) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ArchiveDialog(document: document),
    );
    if (reason == null || !mounted) return;

    final ok = await ref.read(documentsActionControllerProvider.notifier).archiveDocument(
          documentId: document.id,
          reason: reason,
        );
    if (!mounted) return;
    if (ok) _say('Withdrawn from the folder.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documentsAsync = ref.watch(studentDocumentsProvider(widget.studentId));
    final summary = ref.watch(folderSummaryProvider(widget.studentId));
    final working = ref.watch(documentsActionControllerProvider).isLoading;

    // Failures from the controller surface here rather than at each call
    // site, so a permission refusal reads the same wherever it came from.
    ref.listen(documentsActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) _say('$error');
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.studentName, style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: working ? null : _fileDocument,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('File a document'),
            ),
      body: documentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'The folder could not be opened',
          detail: '$e',
        ),
        data: (documents) {
          final shown =
              documents.where((d) => _showArchived || !d.isArchived).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (working) const LinearProgressIndicator(minHeight: 2),
              _FolderHeader(
                summary: summary,
                showArchived: _showArchived,
                onToggleArchived: summary.archived == 0
                    ? null
                    : () => setState(() => _showArchived = !_showArchived),
              ),
              const Divider(height: 1),
              Expanded(
                child: shown.isEmpty
                    ? _Message(
                        icon: Icons.folder_open_outlined,
                        title: documents.isEmpty
                            ? 'Nothing on file yet'
                            : 'Nothing on file right now',
                        detail: widget.readOnly
                            ? 'The school has not recorded any documents for '
                                '${widget.studentName} yet.'
                            : 'Scanned documents filed here stay with the '
                                'student record. Copies of anything released '
                                'are filed automatically.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _DocumentTile(
                          document: shown[i],
                          readOnly: widget.readOnly,
                          onOpen: () => openAttachment(
                            context,
                            url: shown[i].url,
                            fileName: shown[i].fileName,
                          ),
                          onArchive: working ? null : () => _archive(shown[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  final FolderSummary summary;
  final bool showArchived;
  final VoidCallback? onToggleArchived;

  const _FolderHeader({
    required this.summary,
    required this.showArchived,
    required this.onToggleArchived,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary.isEmpty
                  ? 'No documents on file'
                  : '${summary.onFile} on file',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (summary.archived > 0)
            TextButton.icon(
              onPressed: onToggleArchived,
              icon: Icon(showArchived
                  ? Icons.visibility_off_outlined
                  : Icons.history_outlined),
              label: Text(
                showArchived
                    ? 'Hide withdrawn'
                    : 'Show ${summary.archived} withdrawn',
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final StudentDocument document;
  final bool readOnly;
  final VoidCallback onOpen;
  final VoidCallback? onArchive;

  const _DocumentTile({
    required this.document,
    required this.readOnly,
    required this.onOpen,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Opacity(
      // Withdrawn papers stay legible but stop competing with what is
      // actually on file.
      opacity: document.isArchived ? 0.6 : 1,
      child: ListTile(
        onTap: onOpen,
        leading: Icon(
          document.isIssuedCopy
              ? Icons.outbound_outlined
              : Icons.description_outlined,
          color: document.isArchived ? theme.disabledColor : null,
        ),
        title: Text(
          document.title,
          style: TextStyle(
            decoration: document.isArchived ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${document.kind.displayLabel} · ${document.sizeLabel} · '
              'filed ${_dateFormat.format(document.filedAt)} by '
              '${document.filedByName}',
              style: muted,
            ),
            if (document.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(document.note!, style: muted),
              ),
            if (document.isArchived)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Withdrawn ${_dateFormat.format(document.archivedAt!)} by '
                  '${document.archivedByName ?? 'the office'} — '
                  '${document.archiveReason ?? 'no reason recorded'}',
                  style: muted?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
        isThreeLine: document.note != null || document.isArchived,
        trailing: readOnly || document.isArchived
            ? null
            : IconButton(
                tooltip: 'Withdraw from the folder',
                icon: const Icon(Icons.archive_outlined),
                onPressed: onArchive,
              ),
      ),
    );
  }
}

class _FilingChoice {
  final DocumentKind kind;
  final String title;
  final String? note;
  const _FilingChoice({required this.kind, required this.title, this.note});
}

/// What is being filed, asked before the file picker opens.
///
/// In that order on purpose: picking a file and then being asked what it
/// was means the dialog can be dismissed after the bytes are already in
/// hand, and the obvious implementation then uploads them anyway.
class _FileDocumentSheet extends StatefulWidget {
  const _FileDocumentSheet();

  @override
  State<_FileDocumentSheet> createState() => _FileDocumentSheetState();
}

class _FileDocumentSheetState extends State<_FileDocumentSheet> {
  DocumentKind _kind = DocumentKind.birthCertificate;
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('File a document', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<DocumentKind>(
            initialValue: _kind,
            decoration: const InputDecoration(
              labelText: 'What is it',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final kind in DocumentKind.fileable)
                DropdownMenuItem(value: kind, child: Text(kind.displayLabel)),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Name on the folder (optional)',
              hintText: _kind.displayLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Original sighted, photocopy on file',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _FilingChoice(
                kind: _kind,
                title: _titleController.text,
                note: _noteController.text,
              ),
            ),
            icon: const Icon(Icons.attach_file),
            label: const Text('Choose the scan'),
          ),
          const SizedBox(height: 8),
          Text(
            'PDFs and photos, up to 10MB.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Asks why, and will not take an empty answer.
class _ArchiveDialog extends StatefulWidget {
  final StudentDocument document;
  const _ArchiveDialog({required this.document});

  @override
  State<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends State<_ArchiveDialog> {
  final _controller = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    final tooShort = reason.length < 4;
    return AlertDialog(
      title: const Text('Withdraw from the folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.document.title}" stays on the record as withdrawn. '
            'Nothing is deleted.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Why',
              hintText: 'Superseded by the corrected copy',
              border: const OutlineInputBorder(),
              errorText: _tried && tooShort ? 'Say why it is being withdrawn.' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (tooShort) {
              setState(() => _tried = true);
              return;
            }
            Navigator.of(context).pop(reason);
          },
          child: const Text('Withdraw'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _Message({required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              detail,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
