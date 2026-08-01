import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'csv.dart';

/// Shared export/import UI for the staff portals.
///
/// Every portal exports a list and some import one, and the awkward parts
/// are identical everywhere: picking a file, decoding it, telling the user
/// which rows are wrong, and not applying anything until they have seen
/// that. Doing it once means a portal only supplies its columns and a row
/// parser.
class ExportImportSheet<T> extends StatefulWidget {
  /// What is being moved, for the labels: "students", "employees".
  final String label;

  /// Column headers, in order, for both export and the import template.
  final List<String> headers;

  /// Current records as rows, in the same order as [headers].
  final List<List<String>> Function() rows;

  /// Parses one data row (header already stripped) into a record, or
  /// returns an error message. Null means "skip this row silently".
  final Object? Function(List<String> row, int rowNumber)? parseRow;

  /// Applies the parsed records. Only called after the user confirms, and
  /// only when there are no blocking issues.
  final Future<int> Function(List<Object> records)? onImport;

  const ExportImportSheet({
    super.key,
    required this.label,
    required this.headers,
    required this.rows,
    this.parseRow,
    this.onImport,
  });

  @override
  State<ExportImportSheet<T>> createState() => _ExportImportSheetState<T>();
}

class _ExportImportSheetState<T> extends State<ExportImportSheet<T>> {
  ImportResult<Object>? _preview;
  bool _busy = false;

  bool get _importSupported => widget.parseRow != null && widget.onImport != null;

  Future<void> _export() async {
    final csv = Csv.encode(widget.headers, widget.rows());
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final stamp = DateTime.now().toIso8601String().substring(0, 10);

    // sharePdf despite the name is the package's generic "hand these bytes
    // to the platform" call -- on web it downloads, on mobile it opens the
    // share sheet. Saves adding a second file-IO dependency.
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${widget.label.toLowerCase().replaceAll(' ', '-')}-$stamp.csv',
    );
  }

  /// Downloads a header-only file, so a user importing for the first time
  /// starts from the exact columns the parser expects rather than guessing.
  Future<void> _downloadTemplate() async {
    final csv = Csv.encode(widget.headers, const []);
    await Printing.sharePdf(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      filename: '${widget.label.toLowerCase().replaceAll(' ', '-')}-template.csv',
    );
  }

  Future<void> _pickAndPreview() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _busy = true);
    final table = Csv.decode(utf8.decode(file!.bytes!, allowMalformed: true));
    final records = <Object>[];
    final issues = <ImportIssue>[];

    if (table.isEmpty) {
      issues.add(const ImportIssue(0, 'The file is empty.'));
    } else {
      // Header check first: a mismatched file produces a wall of
      // per-row errors that all mean the same thing, which is worse
      // than one clear message.
      final header = table.first.map((h) => h.trim().toLowerCase()).toList();
      final expected = widget.headers.map((h) => h.toLowerCase()).toList();
      if (header.length != expected.length ||
          !List.generate(expected.length, (i) => header[i] == expected[i]).every((e) => e)) {
        issues.add(ImportIssue(
          1,
          'Columns do not match. Expected: ${widget.headers.join(", ")}',
        ));
      } else {
        for (var i = 1; i < table.length; i++) {
          final rowNumber = i + 1; // 1-based, counting the header
          final parsed = widget.parseRow!(table[i], rowNumber);
          if (parsed == null) continue;
          if (parsed is ImportIssue) {
            issues.add(parsed);
          } else if (parsed is String) {
            issues.add(ImportIssue(rowNumber, parsed));
          } else {
            records.add(parsed);
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _preview = ImportResult(records: records, issues: issues);
    });
  }

  Future<void> _applyImport() async {
    final preview = _preview;
    if (preview == null || preview.records.isEmpty) return;

    setState(() => _busy = true);
    final count = await widget.onImport!(preview.records);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Imported $count ${widget.label.toLowerCase()}.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export / Import ${widget.label}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download_outlined),
              label: Text('Export ${widget.rows().length} ${widget.label.toLowerCase()} to CSV'),
            ),
            if (_importSupported) ...[
              const Divider(height: 32),
              TextButton.icon(
                onPressed: _busy ? null : _downloadTemplate,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Download blank template'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickAndPreview,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Choose a CSV to import'),
              ),
              if (preview != null) ...[
                const SizedBox(height: 16),
                if (preview.hasIssues)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            Text(
                              '${preview.issues.length} problem'
                              '${preview.issues.length == 1 ? '' : 's'} found',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...preview.issues.map(
                              (issue) => Text(
                                issue.toString(),
                                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '${preview.records.length} row'
                  '${preview.records.length == 1 ? '' : 's'} ready to import.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  // Nothing is applied while any row is bad: a partial
                  // import of a spreadsheet is far harder to unpick than
                  // fixing the file and trying again.
                  onPressed: _busy || preview.records.isEmpty || preview.hasIssues
                      ? null
                      : _applyImport,
                  icon: const Icon(Icons.check),
                  label: Text(
                    preview.hasIssues
                        ? 'Fix the problems above first'
                        : 'Import ${preview.records.length}',
                  ),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Import is not available for ${widget.label.toLowerCase()} — '
                  'these records are created through their own screens so the '
                  'checks that apply there are not bypassed.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens the sheet. Kept as a function so callers do not repeat the
/// showModalBottomSheet boilerplate.
Future<void> showExportImportSheet({
  required BuildContext context,
  required String label,
  required List<String> headers,
  required List<List<String>> Function() rows,
  Object? Function(List<String> row, int rowNumber)? parseRow,
  Future<int> Function(List<Object> records)? onImport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ExportImportSheet<Object>(
      label: label,
      headers: headers,
      rows: rows,
      parseRow: parseRow,
      onImport: onImport,
    ),
  );
}
