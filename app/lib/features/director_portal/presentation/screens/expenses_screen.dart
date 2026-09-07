import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:file_picker/file_picker.dart';

import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/data_transfer/open_attachment.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/expense.dart';
import '../import/expense_import.dart';
import '../controllers/director_controller.dart';
import '../../../../core/widgets/field_tile.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat.yMMMd();

const _categories = ['Utilities', 'Supplies', 'Maintenance', 'Salaries', 'Transportation', 'Other'];

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesStreamProvider);

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Export / Import',
            onPressed: () => _showTransfer(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load expenses: $err')),
        data: (expenses) {
          if (expenses.isEmpty) {
            return const Center(child: Text('No expenses recorded yet.'));
          }
          final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                // The label shrinks, not the figure: a six-digit peso total
                // plus this label overflows a phone-width header otherwise.
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Total (all shown)', overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(_currencyFormat.format(total), style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final e = expenses[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        // The amount sits on the title row rather than in
                        // `trailing`. ListTile passes its trailing slot
                        // unbounded width, so an amount + actions menu Row
                        // there cannot shrink and overflows a phone-width
                        // screen; the title slot is bounded, so Expanded
                        // works and the description ellipsizes instead.
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(e.description, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currencyFormat.format(e.amount),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${e.category} · ${_dateFormat.format(e.date)} · ${e.recordedByName}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Said either way. An expense with no receipt
                            // is a state the office needs to see, not one
                            // to leave blank and hope somebody notices.
                            if (e.hasReceipt)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => openAttachment(
                                  context,
                                  url: e.receiptUrl!,
                                  fileName: e.receiptFileName,
                                ),
                                icon: const Icon(Icons.receipt_long, size: 16),
                                label: const Text('Receipt'),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'No receipt',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                        trailing: RowActionsMenu(
                          onEdit: () => _showEditor(context, ref, existing: e),
                          onDelete: () => _confirmDelete(context, ref, e),
                        ),
                      ),
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

  /// Export, and import.
  ///
  /// Recorded By exports but does not import: it names who entered the
  /// spending and the server stamps it from the signed-in user, so a
  /// column that let a file claim otherwise would put someone else's
  /// name against money they never recorded. Importing therefore records
  /// the spending under whoever uploaded the file, which is the honest
  /// reading -- they are the one putting it in the ledger.
  void _showTransfer(BuildContext context, WidgetRef ref) {
    final expenses = ref.read(expensesStreamProvider).valueOrNull ?? const <Expense>[];
    // Per file, not per row: a workbook pasted in twice is one mistake,
    // and it has to be caught across the whole file to be caught at all.
    final seen = <String>{};
    showExportImportSheet(
      context: context,
      label: 'Expenses',
      headers: const ['Date', 'Category', 'Description', 'Amount', 'Recorded By'],
      importHeaders: const ['Date', 'Category', 'Description', 'Amount'],
      importNote:
          'Every imported expense is recorded under your name — Recorded By '
          'is exported for the record but ignored on the way back in. '
          'Category must be one of: ${_categories.join(', ')}. Dates can be '
          'a date cell or written as 2026-03-07.',
      rows: () => expenses
          .map((e) => [
                _dateFormat.format(e.date),
                e.category,
                e.description,
                e.amount.toStringAsFixed(2),
                e.recordedByName,
              ])
          .toList(),
      parseRow: (row, rowNumber) => ExpenseImport.parseRow(
        row: row,
        rowNumber: rowNumber,
        categories: _categories,
        existing: expenses,
        seen: seen,
      ),
      onImport: (records) async {
        final controller = ref.read(directorActionControllerProvider.notifier);
        // Counted as they land rather than assumed from the row count:
        // the difference between "9 of 40 imported, something is wrong"
        // and a Director trusting a total that was never written.
        var imported = 0;
        for (final r in records.cast<ExpenseImportRow>()) {
          final ok = await controller.createExpense(
            category: r.category,
            description: r.description,
            amount: r.amount,
            date: r.date,
          );
          if (ok) imported++;
        }
        return imported;
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Expense e) async {
    final ok = await confirmDelete(context, itemLabel: 'expense', detail: e.description);
    if (!ok) return;
    await ref.read(directorActionControllerProvider.notifier).deleteExpense(e.id);
  }

  /// Picks a receipt and uploads it, or returns null.
  ///
  /// Silent on a cancelled pick, loud on a failed upload: the first is
  /// somebody changing their mind, the second is an expense about to be
  /// saved with nothing behind it and no indication why.
  Future<UploadedFile?> _pickReceipt(WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      // Matches storage.rules, which accepts images and PDFs only.
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return null;

    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.expenseReceipts,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType:
              file.extension == 'pdf' ? 'application/pdf' : 'image/${file.extension}',
        );
    if (result case Success<UploadedFile>(:final value)) return value;
    return null;
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, {Expense? existing}) async {
    final isEdit = existing != null;
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final amountController =
        TextEditingController(text: existing != null ? existing.amount.toString() : '');
    // An edited expense may carry a category the current catalogue no
    // longer lists; keep it rather than silently reassigning the row.
    String category = existing != null && _categories.contains(existing.category)
        ? existing.category
        : _categories.first;
    DateTime date = existing?.date ?? DateTime.now();
    // Seeded from the row being edited, and sent back on save whether or
    // not anybody touched it. The update path writes this field
    // unconditionally, so a dialog that did not carry it detached the
    // receipt from every expense anybody ever corrected a typo on.
    String? receiptUrl = existing?.receiptUrl;
    String? receiptFileName = existing?.receiptFileName;
    var uploading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(isEdit ? 'Edit Expense' : 'Record Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₱)'),
                ),
                const SizedBox(height: 12),
                FieldTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: _dateFormat.format(date),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                      initialDate: date,
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                ),
                const SizedBox(height: 8),
                // The substantiation. An expense record with nothing
                // behind it is the spreadsheet this replaces, and the
                // receipt is the first thing anybody auditing the books
                // asks to see.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(receiptUrl == null
                      ? Icons.receipt_long_outlined
                      : Icons.receipt_long),
                  title: Text(
                    receiptUrl == null
                        ? 'No receipt attached'
                        : (receiptFileName ?? 'Receipt attached'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: uploading ? const Text('Uploading...') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (receiptUrl != null)
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: uploading
                              ? null
                              : () => setState(() {
                                    receiptUrl = null;
                                    receiptFileName = null;
                                  }),
                        ),
                      TextButton(
                        onPressed: uploading
                            ? null
                            : () async {
                                setState(() => uploading = true);
                                final picked = await _pickReceipt(ref);
                                setState(() {
                                  uploading = false;
                                  if (picked != null) {
                                    receiptUrl = picked.url;
                                    receiptFileName = picked.fileName;
                                  }
                                });
                              },
                        child: Text(receiptUrl == null ? 'Attach' : 'Replace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? -1;
                final notifier = ref.read(directorActionControllerProvider.notifier);
                final success = isEdit
                    ? await notifier.updateExpense(
                        expenseId: existing.id,
                        category: category,
                        description: descriptionController.text,
                        amount: amount,
                        date: date,
                        receiptUrl: receiptUrl,
                        receiptFileName: receiptFileName,
                      )
                    : await notifier.createExpense(
                        category: category,
                        description: descriptionController.text,
                        amount: amount,
                        date: date,
                        receiptUrl: receiptUrl,
                        receiptFileName: receiptFileName,
                      );
                if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: Text(isEdit ? 'Save Changes' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
