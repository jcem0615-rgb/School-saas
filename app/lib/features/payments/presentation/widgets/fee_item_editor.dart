import 'package:flutter/material.dart';

import '../../domain/entities/fee_structure.dart';

/// One editable fee line, mid-edit.
///
/// Holds its own controllers rather than being rebuilt from a list of
/// values each frame: removing a row from the middle otherwise shifts
/// every row below it up by one, so the text a user typed on line four
/// silently becomes line three's.
///
/// Shared by the fee-schedule editor and the assessment screen because
/// they are the same act -- naming fees and pricing them -- once as a
/// template and once against a student.
class FeeItemDraft {
  final TextEditingController labelController;
  final TextEditingController amountController;
  FeeCategory category;

  FeeItemDraft._(this.labelController, this.amountController, this.category);

  factory FeeItemDraft.blank() =>
      FeeItemDraft._(TextEditingController(), TextEditingController(), FeeCategory.tuition);

  factory FeeItemDraft.from(FeeItem item) => FeeItemDraft._(
        TextEditingController(text: item.label),
        TextEditingController(text: item.amount.toStringAsFixed(2)),
        item.category,
      );

  /// Null while the field is blank or half-typed. Callers treat that as
  /// zero and let the use case refuse it by name -- "Laboratory Fee must
  /// cost more than zero" says which line to look at, where dropping the
  /// row silently would not.
  double? get amount => double.tryParse(amountController.text.trim());

  FeeItem toItem() => FeeItem(
        label: labelController.text.trim(),
        amount: amount ?? 0,
        category: category,
      );

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

/// Sums a draft list, treating unparseable amounts as zero so the running
/// total does not jump around while somebody is typing.
double draftTotal(Iterable<FeeItemDraft> drafts) =>
    drafts.fold(0, (sum, draft) => sum + (draft.amount ?? 0));

class FeeItemRow extends StatelessWidget {
  final FeeItemDraft draft;
  final VoidCallback onChanged;

  /// Null makes the row unremovable -- used for the last line of a
  /// schedule, which cannot be saved empty anyway.
  final VoidCallback? onRemove;

  const FeeItemRow({
    super.key,
    required this.draft,
    required this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: draft.labelController,
                  decoration: const InputDecoration(labelText: 'Fee', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₱)', isDense: true),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove fee',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              children: [
                for (final category in FeeCategory.values)
                  ChoiceChip(
                    label: Text(category.displayLabel),
                    visualDensity: VisualDensity.compact,
                    selected: draft.category == category,
                    onSelected: (_) {
                      draft.category = category;
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
