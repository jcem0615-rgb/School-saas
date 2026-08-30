import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/assessment.dart';
import '../../domain/entities/installment.dart';
import '../../domain/entities/payment.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dueFormat = DateFormat('d MMM y');

/// When the money is expected, and whether it has arrived.
///
/// The screen a family opens on the day the reminder lands. It is
/// deliberately the same widget the cashier sees: the two of them
/// disagreeing about what is owed on which date is the argument this
/// feature exists to prevent, and one widget cannot disagree with itself.
///
/// Nothing here is stored. The standing is computed from the plan and the
/// payments every time it is built, which is why it cannot drift from the
/// balance and why a back-dated payment corrects the whole column the
/// moment it is recorded.
class PaymentPlanCard extends StatelessWidget {
  final List<Assessment> assessments;
  final List<Payment> payments;

  /// Injectable so a test can stand on a fixed day rather than on
  /// whenever it happened to run. A schedule test that passes in
  /// September and fails in October is worse than no test.
  final DateTime? asOf;

  const PaymentPlanCard({
    super.key,
    required this.assessments,
    required this.payments,
    this.asOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = asOf ?? DateTime.now();

    // Only when the school actually published a plan.
    //
    // Assessment.combinedSchedule deliberately turns a plan-less charge
    // into a line falling due the day it was made, because the overdue
    // report must not quietly excuse an ad-hoc fee from ever being late.
    // That is right for the report and wrong here: it would show every
    // school a "Payment plan" card containing one invented row, and a
    // school that bills in one lump would reasonably read it as the app
    // making terms up. So the card asks a narrower question than the
    // report does.
    final published = assessments.any((a) => a.hasSchedule);
    if (!published) return const SizedBox.shrink();

    final schedule = Assessment.combinedSchedule(assessments);
    if (schedule.isEmpty) return const SizedBox.shrink();

    final paid = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final lines = schedule.standing(paid: paid, asOf: today);
    final overdue = schedule.overdueAmount(paid: paid, asOf: today);
    final next = schedule.nextDue(paid: paid, asOf: today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment plan', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _headline(overdue: overdue, next: next),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: overdue > 0 ? theme.colorScheme.error : null,
                fontWeight: overdue > 0 ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in lines) _InstallmentRow(standing: line),
            const SizedBox(height: 12),
            Text(
              // Said plainly, because the alternative reading -- that each
              // payment is tied to a particular instalment -- is what makes
              // a family think an early payment did not count.
              'Payments are applied to the earliest unpaid instalment first, '
              'so paying ahead counts against what comes next.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _headline({required double overdue, required InstallmentStanding? next}) {
    if (overdue > 0) {
      final label = next?.installment.label;
      return label == null
          ? '${_currency.format(overdue)} overdue.'
          : '${_currency.format(overdue)} overdue — $label was due '
              '${_dueFormat.format(next!.installment.dueDate)}.';
    }
    if (next == null) return 'Fully paid. Nothing further is due.';
    return 'Up to date. Next: ${next.installment.label}, '
        '${_currency.format(next.outstanding)} on '
        '${_dueFormat.format(next.installment.dueDate)}.';
  }
}

class _InstallmentRow extends StatelessWidget {
  final InstallmentStanding standing;
  const _InstallmentRow({required this.standing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = standing.state == InstallmentState.overdue;
    final paid = standing.state == InstallmentState.paid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            paid
                ? Icons.check_circle
                : overdue
                    ? Icons.error_outline
                    : Icons.schedule,
            size: 18,
            color: paid
                ? theme.colorScheme.primary
                : overdue
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(standing.installment.label, style: theme.textTheme.bodyMedium),
                Text(
                  _subtitle(standing),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: overdue ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _currency.format(standing.installment.amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              // Struck through rather than hidden: a family checking what
              // they paid in August needs the figure to still be there.
              decoration: paid ? TextDecoration.lineThrough : null,
              color: paid ? theme.colorScheme.outline : null,
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(InstallmentStanding standing) {
    final due = _dueFormat.format(standing.installment.dueDate);
    return switch (standing.state) {
      InstallmentState.paid => 'Paid · due $due',
      InstallmentState.partial =>
        '${_currency.format(standing.outstanding)} left · due $due',
      InstallmentState.overdue => standing.daysLate == 1
          ? 'Overdue by 1 day · was due $due'
          : 'Overdue by ${standing.daysLate} days · was due $due',
      InstallmentState.upcoming => 'Due $due',
    };
  }
}
