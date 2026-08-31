import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/subsidy.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// One government subsidy, mid-edit.
class SubsidyDraft {
  SubsidyProgramme programme;
  final TextEditingController referenceController;
  final TextEditingController amountController;

  SubsidyDraft._(this.programme, this.referenceController, this.amountController);

  factory SubsidyDraft.blank() => SubsidyDraft._(
        SubsidyProgramme.esc,
        TextEditingController(),
        TextEditingController(),
      );

  double? get amount => double.tryParse(amountController.text.trim());

  bool get isComplete =>
      referenceController.text.trim().isNotEmpty && (amount ?? 0) > 0;

  /// [recordedByName] is stamped server-side from the caller's token;
  /// what is passed here is only for the on-screen preview.
  Subsidy toSubsidy(String recordedByName) => Subsidy(
        programme: programme,
        referenceNumber: referenceController.text.trim(),
        amount: amount ?? 0,
        recordedByName: recordedByName,
      );

  void dispose() {
    referenceController.dispose();
    amountController.dispose();
  }
}

/// The ESC / voucher section of the assess-fees screen.
///
/// Kept separate from the discount editor above it on purpose. They look
/// alike and mean opposite things -- one is money the school gave away,
/// the other money the school is owed -- and a bursar filing an ESC grant
/// under "discount" is the mistake that makes the year-end figures wrong
/// in both directions at once.
class SubsidyEditor extends StatelessWidget {
  final List<SubsidyDraft> drafts;

  /// What is still chargeable after the discounts. The grants cannot come
  /// to more than this.
  final double chargeableAfterDiscounts;

  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onChanged;

  const SubsidyEditor({
    super.key,
    required this.drafts,
    required this.chargeableAfterDiscounts,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  double get _granted =>
      drafts.fold(0, (sum, d) => sum + (d.isComplete ? d.amount! : 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = _granted;
    final overGranted = granted > chargeableAfterDiscounts + 0.005;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Government subsidies', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          drafts.isEmpty
              ? 'ESC grants and SHS vouchers. Recorded apart from discounts '
                  'because this is money the school will bill DepEd for, not '
                  'money it gave away.'
              : 'The certificate number is what the school bills against. '
                  'Without it the grant cannot be claimed.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < drafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SubsidyRow(
              key: ObjectKey(drafts[i]),
              draft: drafts[i],
              onChanged: onChanged,
              onRemove: () => onRemove(i),
            ),
          ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(drafts.isEmpty ? 'Add a subsidy' : 'Add another'),
        ),
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: overGranted
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              overGranted
                  ? 'The subsidies come to ${_currency.format(granted)} against '
                      '${_currency.format(chargeableAfterDiscounts)} still '
                      'chargeable. A grant can cover the whole of what is left '
                      'and no more.'
                  : 'Claimable from DepEd ${_currency.format(granted)} — the '
                      'family is left with '
                      '${_currency.format(chargeableAfterDiscounts - granted)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: overGranted ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubsidyRow extends StatelessWidget {
  final SubsidyDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _SubsidyRow({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: DropdownButtonFormField<SubsidyProgramme>(
            initialValue: draft.programme,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Programme', isDense: true),
            items: [
              for (final programme in SubsidyProgramme.values)
                DropdownMenuItem(
                    value: programme, child: Text(programme.displayLabel)),
            ],
            onChanged: (programme) {
              if (programme == null) return;
              draft.programme = programme;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: TextField(
            controller: draft.referenceController,
            decoration: InputDecoration(
              // The label follows the programme, because ESC and the
              // voucher programme call this different things and a bursar
              // is copying from whichever form is in front of them.
              labelText: draft.programme.referenceLabel,
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
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
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          tooltip: 'Remove subsidy',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
