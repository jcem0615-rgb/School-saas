import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/assessment.dart';
import '../../domain/entities/payment.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat('d MMM y');

/// How a balance got to be what it is.
///
/// This is the whole reason assessments exist. A balance used to be one
/// number: payments reduced it and a registrar typed the opening figure
/// by hand, so a family asking "why do we owe 8,500?" got the figure back
/// and nothing else. Charged minus paid, itemised, answers it.
///
/// The arithmetic is stated even when it does not come out, and that is
/// deliberate. A school partway through adopting this has students whose
/// balance was set the old way, with no assessment behind it; showing
/// only the assessments there would imply the list is the whole story
/// and quietly understate what is owed. Naming the unexplained remainder
/// is the honest version, and it also tells the office exactly which
/// records still need an assessment raising.
class BalanceBreakdown extends StatelessWidget {
  final double balance;
  final List<Assessment> assessments;
  final List<Payment> payments;

  const BalanceBreakdown({
    super.key,
    required this.balance,
    required this.assessments,
    required this.payments,
  });

  double get _charged => assessments.fold(0, (sum, a) => sum + a.effectiveTotal);

  /// Every row, summed as it stands.
  ///
  /// A refund is its own row with a negative amount, and the payment it
  /// reverses keeps its positive one (marked `refunded`) rather than
  /// being edited away -- so the pair cancels out on its own. Filtering
  /// either of them out is what breaks this: dropping the refund row
  /// counts money the school gave back as still received, and dropping
  /// the refunded original counts the reversal without the payment,
  /// which is worse. Both show up as a phantom remainder against a
  /// balance that is perfectly correct.
  double get _paid => payments.fold(0, (sum, p) => sum + p.amount);

  /// What the assessments and payments on file do not account for.
  ///
  /// Rounded before comparing: floating point makes 17000 - 8500 - 8500
  /// come out as 1.8e-12 often enough to matter, and a stray centavo
  /// warning on a balance that reconciles perfectly is worse than none.
  double get _unexplained => ((balance - (_charged - _paid)) * 100).round() / 100;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How this balance is made up', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _Line(label: 'Total assessed', amount: _charged),
            _Line(label: 'Less payments received', amount: -_paid),
            if (_unexplained != 0)
              _Line(
                label: 'Not covered by an assessment',
                amount: _unexplained,
                muted: true,
              ),
            const Divider(height: 20),
            _Line(label: 'Balance', amount: balance, bold: true),
            if (_unexplained != 0) ...[
              const SizedBox(height: 10),
              Text(
                _unexplained > 0
                    ? 'Part of this balance was set directly rather than assessed, '
                        'so it has no itemised breakdown. Raising an assessment for '
                        'it would give the family something they can read.'
                    : 'Part of this balance was written off or corrected directly '
                        'rather than by a payment or a voided assessment, so there '
                        'is no record here of what changed it.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (assessments.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Assessments', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final a in assessments) _AssessmentTile(assessment: a),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;
  final bool muted;

  const _Line({
    required this.label,
    required this.amount,
    this.bold = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(
      fontWeight: bold ? FontWeight.bold : null,
      color: muted ? theme.colorScheme.onSurfaceVariant : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: style)),
          Text(_currency.format(amount), style: style),
        ],
      ),
    );
  }
}

/// One assessment, expandable to its items.
///
/// Collapsed by default: a family checking a balance wants the total and
/// the date first, and four fee lines under every assessment turns the
/// screen into a wall before anyone has decided which one they are asking
/// about.
class _AssessmentTile extends StatelessWidget {
  final Assessment assessment;
  const _AssessmentTile({required this.assessment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voided = assessment.isVoided;

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      title: Text(
        assessment.sourceLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        '${assessment.schoolYear} · ${_dateFormat.format(assessment.assessedAt)}'
        '${voided ? ' · Voided' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        _currency.format(assessment.total),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      children: [
        for (final item in assessment.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item.label}  ·  ${item.category.displayLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(_currency.format(item.amount), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        // What was taken off, itemised, in the school's own words. The
        // trailing figure above is the net, so without these lines a
        // family holding a printed schedule of fees sees a smaller number
        // here with nothing explaining the difference -- which reads as
        // the system being wrong rather than as a discount being granted.
        if (assessment.discounts.isNotEmpty) ...[
          const Divider(height: 12),
          for (final discount in assessment.discounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      discount.displayLine,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  Text(
                    '-${_currency.format(discount.amount)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Fees ${_currency.format(assessment.grossTotal)}, '
              'less ${_currency.format(assessment.discountTotal)} '
              'granted by ${assessment.discounts.first.approvedByName}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        if (assessment.remarks != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(assessment.remarks!, style: theme.textTheme.bodySmall),
          ),
        // The reversal is shown on the assessment it reversed, not as a
        // separate row. Somebody looking at a voided charge is asking why
        // it was voided.
        if (voided)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Voided by ${assessment.voidedByName ?? 'the office'}'
              '${assessment.voidReason == null ? '' : ' — ${assessment.voidReason}'}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
