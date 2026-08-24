import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'csv.dart';
import 'import_columns.dart';
import 'workbook.dart';

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

  /// Column headers, in order, for the exported file.
  final List<String> headers;

  /// Columns the importer needs, if they differ from [headers].
  ///
  /// They usually do. An export shows everything a record has, including
  /// the fields the server owns -- a student number, a balance. An import
  /// can only supply the fields a person is allowed to set, and asking
  /// them to fill in a Student Number column that will be ignored invites
  /// exactly the assumption that it will not be.
  final List<String>? importHeaders;

  /// One line under the import controls explaining anything surprising
  /// about what will happen -- typically which fields the server assigns.
  final String? importNote;

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
    this.importHeaders,
    this.importNote,
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

  List<String> get _importHeaders => widget.importHeaders ?? widget.headers;

  String get _slug => widget.label.toLowerCase().replaceAll(' ', '-');

  /// Hands [bytes] to the platform's save dialog (a download, on web).
  ///
  /// Not `Printing.sharePdf`, which the export used to go through: it
  /// labels every blob `application/pdf` regardless of what is in it, so
  /// a workbook arrived as a PDF that Excel had to be argued into
  /// opening, and Android's share sheet offered it to PDF readers.
  Future<void> _save(Uint8List bytes, String filename, String extension) async {
    await FilePicker.saveFile(
      fileName: filename,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
  }

  String get _stamp => DateTime.now().toIso8601String().substring(0, 10);

  /// The default, because it is the one that survives the trip.
  Future<void> _exportWorkbook() async {
    final bytes = Workbook.encode(widget.headers, widget.rows(), sheetName: widget.label);
    await _save(bytes, '$_slug-$_stamp.xlsx', 'xlsx');
  }

  /// Still offered, for whatever the school's other system eats.
  Future<void> _exportCsv() async {
    final csv = Csv.encode(widget.headers, widget.rows());
    // The BOM is not decoration. Without it Excel on a Windows machine
    // set to a Philippine locale reads the file in the system codepage,
    // and every enye in the roster arrives as mojibake.
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    await _save(bytes, '$_slug-$_stamp.csv', 'csv');
  }

  /// A header-only workbook, so a first-time import starts from the exact
  /// columns the parser expects rather than from a guess.
  Future<void> _downloadTemplate() async {
    final bytes = Workbook.encode(_importHeaders, const [], sheetName: widget.label);
    await _save(bytes, '$_slug-template.xlsx', 'xlsx');
  }

  Future<void> _pickAndPreview() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _busy = true);

    final records = <Object>[];
    final issues = <ImportIssue>[];
    List<List<String>> table;
    try {
      table = _readTable(file!);
    } catch (err) {
      // A workbook that will not open is one message, not a parse error
      // per row. The most common cause by far is the old .xls format,
      // which is a different container entirely, so say so.
      setState(() {
        _busy = false;
        _preview = const ImportResult(records: [], issues: [
          ImportIssue(0,
              'That file could not be read. Save it as .xlsx or .csv and try '
              'again — the older .xls format is not supported.'),
        ]);
      });
      return;
    }

    if (table.isEmpty) {
      issues.add(const ImportIssue(0, 'The file is empty.'));
    } else {
      final mapping = ImportColumns.resolve(table.first, _importHeaders);
      if (mapping is ImportIssue) {
        // Header trouble first and alone: a mismatched file produces a
        // wall of per-row errors that all mean the same thing, which is
        // worse than one clear message.
        issues.add(mapping);
      } else {
        final columns = mapping as List<int>;
        for (var i = 1; i < table.length; i++) {
          final rowNumber = i + 1; // 1-based, counting the header
          final row = table[i];
          if (row.every((cell) => cell.trim().isEmpty)) continue;
          final parsed = widget.parseRow!(ImportColumns.reorder(row, columns), rowNumber);
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

  /// Decides by extension, not by sniffing: a file named .csv that holds
  /// a workbook is a mistake worth reporting rather than one to paper
  /// over.
  List<List<String>> _readTable(PlatformFile file) {
    final isWorkbook = (file.extension ?? '').toLowerCase() == 'xlsx';
    if (isWorkbook) return Workbook.decode(file.bytes!);
    var text = utf8.decode(file.bytes!, allowMalformed: true);
    // Excel writes a BOM on "CSV UTF-8"; left in, it becomes part of the
    // first header and nothing matches.
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return Csv.decode(text);
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
        // Deeper at the bottom than the sides: this is the last thing in
        // a sheet that can run past the fold, and on a phone the closing
        // line of the import note otherwise sits flush against the edge
        // of the screen looking cut off.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export / Import ${widget.label}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _exportWorkbook,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                'Export ${widget.rows().length} ${widget.label.toLowerCase()} to Excel',
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy ? null : _exportCsv,
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Export as CSV instead'),
            ),
            Text(
              'The Excel file (.xlsx) opens in Microsoft Excel, WPS Office '
              'and Google Sheets, and keeps student numbers and phone '
              'numbers exactly as they are.',
              style: theme.textTheme.bodySmall,
            ),
            if (_importSupported) ...[
              const Divider(height: 32),
              Text('Bulk import', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _downloadTemplate,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Download blank template (.xlsx)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickAndPreview,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Choose an Excel or CSV file'),
              ),
              if (widget.importNote != null) ...[
                const SizedBox(height: 8),
                Text(widget.importNote!, style: theme.textTheme.bodySmall),
              ],
              if (_busy && _preview == null) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
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
  List<String>? importHeaders,
  String? importNote,
  Object? Function(List<String> row, int rowNumber)? parseRow,
  Future<int> Function(List<Object> records)? onImport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The import preview can run to a screenful of issues, and a sheet
    // that cannot scroll would hide the row numbers someone needs.
    builder: (_) => SingleChildScrollView(
      child: ExportImportSheet<Object>(
        label: label,
        headers: headers,
        rows: rows,
        importHeaders: importHeaders,
        importNote: importNote,
        parseRow: parseRow,
        onImport: onImport,
      ),
    ),
  );
}
