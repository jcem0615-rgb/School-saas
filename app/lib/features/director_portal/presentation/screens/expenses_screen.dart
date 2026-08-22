import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/expense.dart';
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
                        subtitle: Text('${e.category} · ${_dateFormat.format(e.date)} · ${e.recordedByName}'),
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

  /// Export only: expenses carry a recordedByName the audit trail relies
  /// on, and a bulk import would attribute someone else's spending to
  /// whoever uploaded the file.
  void _showTransfer(BuildContext context, WidgetRef ref) {
    final expenses = ref.read(expensesStreamProvider).valueOrNull ?? const <Expense>[];
    showExportImportSheet(
      context: context,
      label: 'Expenses',
      headers: const ['Date', 'Category', 'Description', 'Amount', 'Recorded By'],
      rows: () => expenses
          .map((e) => [
                _dateFormat.format(e.date),
                e.category,
                e.description,
                e.amount.toStringAsFixed(2),
                e.recordedByName,
              ])
          .toList(),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Expense e) async {
    final ok = await confirmDelete(context, itemLabel: 'expense', detail: e.description);
    if (!ok) return;
    await ref.read(directorActionControllerProvider.notifier).deleteExpense(e.id);
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
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₱)', border: OutlineInputBorder()),
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
                      )
                    : await notifier.createExpense(
                        category: category,
                        description: descriptionController.text,
                        amount: amount,
                        date: date,
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
