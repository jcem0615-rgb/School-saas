import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/discount.dart';
import '../../domain/entities/fee_structure.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// One discount, mid-edit.
///
/// A discount is entered one of two ways and a school uses both: "10% of
/// tuition" and "₱2,000 off". Holding a mode rather than two separate row
/// types keeps one row that can be switched, which is what a registrar
/// actually does when the family turns out to qualify for the flat
/// board-approved figure instead.
class DiscountDraft {
  DiscountKind kind;
  final TextEditingController labelController;

  /// The percentage, when [byPercentage]. The peso figure otherwise.
  final TextEditingController valueController;

  bool byPercentage;
  FeeCategory? appliesTo;

  DiscountDraft._(
    this.kind,
    this.labelController,
    this.valueController,
    this.byPercentage,
    this.appliesTo,
  );

  factory DiscountDraft.blank() => DiscountDraft._(
        DiscountKind.sibling,
        TextEditingController(text: DiscountKind.sibling.displayLabel),
        TextEditingController(),
        true,
        // Tuition by default, because that is what PH private schools
        // discount: the miscellaneous bundle is largely money passed
        // through to third parties, and a school that quietly discounted
        // it would be giving away more than it decided to.
        FeeCategory.tuition,
      );

  double? get value => double.tryParse(valueController.text.trim());

  /// What this comes to against the fees on the screen.
  double amountAgainst(List<FeeItem> items) {
    final entered = value;
    if (entered == null || entered <= 0) return 0;
    if (!byPercentage) return (entered * 100).roundToDouble() / 100;
    return discountAmountFor(
      items: items,
      percentage: entered,
      appliesTo: appliesTo,
    );
  }

  /// [approvedByName] is filled in server-side from the caller's token;
  /// what is passed here is only for the local preview.
  Discount toDiscount(List<FeeItem> items, String approvedByName) => Discount(
        kind: kind,
        label: labelController.text.trim(),
        amount: amountAgainst(items),
        percentage: byPercentage ? value : null,
        appliesTo: byPercentage ? appliesTo : null,
        approvedByName: approvedByName,
      );

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

/// The discount section of the assess-fees screen.
///
/// Optional and collapsed until asked for: most assessments carry none,
/// and a blank row waiting to be filled in reads as a field that must be.
class DiscountEditor extends StatelessWidget {
  final List<DiscountDraft> drafts;

  /// The fees on screen. Percentages are computed against these live, so
  /// a registrar sees the peso figure before granting rather than after.
  final List<FeeItem> items;

  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onChanged;

  const DiscountEditor({
    super.key,
    required this.drafts,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  double get _gross => items.fold(0, (sum, i) => sum + i.amount);
  double get _given => drafts.fold(0, (sum, d) => sum + d.amountAgainst(items));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final given = _given;
    final overGiven = given > _gross + 0.005;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Discounts and scholarships', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          drafts.isEmpty
              ? 'Optional. Recorded as their own lines rather than typed into '
                  'the remarks, so the year-end figure for what the school '
                  'gave away can be produced at all.'
              : 'Taken off what this family is charged. The approver is '
                  'recorded as whoever assesses this.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < drafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DiscountRow(
              key: ObjectKey(drafts[i]),
              draft: drafts[i],
              items: items,
              onChanged: onChanged,
              onRemove: () => onRemove(i),
            ),
          ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(drafts.isEmpty ? 'Add a discount' : 'Add another'),
        ),
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: overGiven
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              overGiven
                  ? 'The discounts come to ${_currency.format(given)} against '
                      'fees of ${_currency.format(_gross)}. A school can waive '
                      'the whole amount, but it cannot charge less than nothing.'
                  : 'Less discounts ${_currency.format(given)} — '
                      'this family is charged ${_currency.format(_gross - given)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: overGiven ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscountRow extends StatelessWidget {
  final DiscountDraft draft;
  final List<FeeItem> items;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _DiscountRow({
    super.key,
    required this.draft,
    required this.items,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = draft.amountAgainst(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<DiscountKind>(
                initialValue: draft.kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kind', isDense: true),
                items: [
                  for (final kind in DiscountKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.displayLabel)),
                ],
                onChanged: (kind) {
                  if (kind == null) return;
                  // Renames the line along with the kind, unless somebody
                  // has already written their own wording -- a label
                  // typed by hand is a decision, and silently replacing
                  // it loses "board resolution 2026-04".
                  final wasDefault = DiscountKind.values.any(
                      (k) => k.displayLabel == draft.labelController.text.trim());
                  draft.kind = kind;
                  if (wasDefault) draft.labelController.text = kind.displayLabel;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: TextField(
                controller: draft.labelController,
                decoration: const InputDecoration(
                  labelText: 'As it appears on the assessment',
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            IconButton(
              tooltip: 'Remove discount',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('%')),
                ButtonSegment(value: false, label: Text('₱')),
              ],
              selected: {draft.byPercentage},
              onSelectionChanged: (selected) {
                draft.byPercentage = selected.first;
                onChanged();
              },
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: draft.valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: draft.byPercentage ? 'Rate' : 'Amount',
                  suffixText: draft.byPercentage ? '%' : null,
                  prefixText: draft.byPercentage ? null : '₱',
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            if (draft.byPercentage)
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<FeeCategory?>(
                  initialValue: draft.appliesTo,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Of', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All fees')),
                    DropdownMenuItem(
                        value: FeeCategory.tuition, child: Text('Tuition')),
                    DropdownMenuItem(
                        value: FeeCategory.miscellaneous,
                        child: Text('Miscellaneous')),
                    DropdownMenuItem(value: FeeCategory.other, child: Text('Other')),
                  ],
                  onChanged: (category) {
                    draft.appliesTo = category;
                    onChanged();
                  },
                ),
              ),
          ],
        ),
        if (amount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Takes off ${_currency.format(amount)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
