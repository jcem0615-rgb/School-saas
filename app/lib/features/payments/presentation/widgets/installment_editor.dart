import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/installment.dart';

final _dueFormat = DateFormat('d MMM y');
final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// One editable instalment, mid-edit.
///
/// Holds its own controllers for the same reason [FeeItemDraft] does:
/// rebuilding rows from a list of values means removing row two silently
/// moves what somebody typed on row three.
class InstallmentDraft {
  final TextEditingController labelController;
  final TextEditingController amountController;
  DateTime dueDate;

  InstallmentDraft._(this.labelController, this.amountController, this.dueDate);

  factory InstallmentDraft.blank({required DateTime dueDate, String label = ''}) =>
      InstallmentDraft._(
        TextEditingController(text: label),
        TextEditingController(),
        dueDate,
      );

  factory InstallmentDraft.from(Installment line) => InstallmentDraft._(
        TextEditingController(text: line.label),
        TextEditingController(text: line.amount.toStringAsFixed(2)),
        line.dueDate,
      );

  double? get amount => double.tryParse(amountController.text.trim());

  Installment toInstallment() => Installment(
        label: labelController.text.trim(),
        dueDate: dueDate,
        amount: amount ?? 0,
      );

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

double draftPlanTotal(Iterable<InstallmentDraft> drafts) =>
    drafts.fold(0, (sum, d) => sum + (d.amount ?? 0));

/// The plan editor, as it appears under the fees on a schedule.
///
/// Optional throughout: a school that bills in one lump adds no rows and
/// nothing about the old behaviour changes. That is why this opens
/// collapsed rather than with a blank row waiting to be filled in --
/// unlike the fee list, where the first thing anyone does is type a fee.
class InstallmentEditor extends StatelessWidget {
  final List<InstallmentDraft> drafts;

  /// What the fees come to. The plan has to match it, and showing the
  /// difference live is the whole point of this widget -- a bursar who
  /// finds out at save time has already typed six rows.
  final double feesTotal;

  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(int index, DateTime date) onDateChanged;

  /// Fills the remaining rows so the plan adds up. Offered rather than
  /// done automatically: a school splitting 45,000 over four payments
  /// usually wants 15,000 down and three of 10,000, not four of 11,250.
  final VoidCallback? onSplitEvenly;

  const InstallmentEditor({
    super.key,
    required this.drafts,
    required this.feesTotal,
    required this.onAdd,
    required this.onRemove,
    required this.onDateChanged,
    this.onSplitEvenly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planned = draftPlanTotal(drafts);
    final difference = ((planned - feesTotal) * 100).round() / 100;
    final balances = drafts.isEmpty || difference.abs() < 0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment plan', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          drafts.isEmpty
              ? 'Optional. Leave this empty and the whole amount falls due when '
                  'it is charged. Add instalments to bill by term or by month.'
              : 'The dates a family is given. Payments are applied to the '
                  'earliest unpaid instalment first.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < drafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _InstallmentRow(
              key: ObjectKey(drafts[i]),
              draft: drafts[i],
              onRemove: () => onRemove(i),
              onPickDate: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: drafts[i].dueDate,
                  // Wide on purpose. A school entering last year's plan to
                  // reconcile an old balance is a real thing, and a picker
                  // that refuses the past makes that impossible.
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime(DateTime.now().year + 3),
                );
                if (picked != null) onDateChanged(i, picked);
              },
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(drafts.isEmpty ? 'Add a payment plan' : 'Add instalment'),
            ),
            if (drafts.isNotEmpty && onSplitEvenly != null)
              TextButton.icon(
                onPressed: onSplitEvenly,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('Split evenly'),
              ),
          ],
        ),
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: balances
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.errorContainer,
            ),
            child: Text(
              balances
                  ? 'Plan totals ${_currency.format(planned)} — matches the fees.'
                  : difference > 0
                      ? 'Plan totals ${_currency.format(planned)}, which is '
                          '${_currency.format(difference)} more than the fees. '
                          'They have to match.'
                      : 'Plan totals ${_currency.format(planned)}, which is '
                          '${_currency.format(difference.abs())} short of the fees. '
                          'They have to match.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: balances ? null : theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  final InstallmentDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onPickDate;

  const _InstallmentRow({
    super.key,
    required this.draft,
    required this.onRemove,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: draft.labelController,
            decoration: const InputDecoration(
              labelText: 'Instalment',
              hintText: 'Upon enrolment',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: OutlinedButton(
            onPressed: onPickDate,
            child: Text(_dueFormat.format(draft.dueDate), maxLines: 1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: draft.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₱',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove instalment',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
