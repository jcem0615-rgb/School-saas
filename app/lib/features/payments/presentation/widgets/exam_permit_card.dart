import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/assessment.dart';
import '../../domain/entities/clearance.dart';
import '../../domain/entities/payment.dart';

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dayFormat = DateFormat('d MMM y');

/// Whether this student may sit the examination, said before they queue.
///
/// A family finding out at the cashier's window on the morning of the
/// exam is the experience this replaces. The card is deliberately shown
/// to the family as well as the office: the point is that nobody is
/// surprised, and a student who can see they are ₱3,400 short a week
/// early is a student whose parent can do something about it.
class ExamPermitCard extends StatelessWidget {
  final List<Assessment> assessments;
  final List<Payment> payments;

  /// Approved promissory notes covering this student.
  final List<PromissoryCover> notes;

  /// Fired when the school lets this person print the slip. Null for the
  /// family: a permit is issued by the cashier, and a self-printed one
  /// would be worth nothing at the door.
  final VoidCallback? onPrint;

  final DateTime? asOf;

  const ExamPermitCard({
    super.key,
    required this.assessments,
    required this.payments,
    this.notes = const [],
    this.onPrint,
    this.asOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = asOf ?? DateTime.now();

    // Nothing published, nothing to be behind on. A school that does not
    // bill in instalments does not gate exams on this, and showing a
    // permanent "Permitted" badge would be a promise the app cannot keep.
    if (!assessments.any((a) => a.hasSchedule)) return const SizedBox.shrink();

    final clearance = clearanceFor(
      schedule: Assessment.combinedSchedule(assessments),
      paid: payments.fold<double>(0, (sum, p) => sum + p.amount),
      asOf: today,
      notes: notes,
    );

    final blocked = clearance.outcome == ClearanceOutcome.blocked;
    final colour = blocked ? theme.colorScheme.error : theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocked ? Icons.gpp_maybe_outlined : Icons.verified_outlined,
                  size: 20,
                  color: colour,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Examination permit', style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _headline(clearance),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: blocked ? colour : null,
                fontWeight: blocked ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(_detail(clearance, today), style: theme.textTheme.bodySmall),
            if (onPrint != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print permit'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _headline(Clearance clearance) => switch (clearance.outcome) {
        ClearanceOutcome.cleared => 'Cleared to take the examination.',
        ClearanceOutcome.clearedByNote =>
          'Cleared on an approved promissory note.',
        ClearanceOutcome.blocked =>
          '${_currency.format(clearance.shortfall)} must be settled before the '
              'examination.',
      };

  static String _detail(Clearance clearance, DateTime today) =>
      switch (clearance.outcome) {
        ClearanceOutcome.cleared =>
          'Nothing is overdue as at ${_dayFormat.format(today)}.',
        ClearanceOutcome.clearedByNote => clearance.note?.settleBy == null
            ? '${_currency.format(clearance.overdue)} is overdue and covered by '
                'a note with no settle-by date.'
            : '${_currency.format(clearance.overdue)} is overdue, to be settled '
                'by ${_dayFormat.format(clearance.note!.settleBy!)}.',
        ClearanceOutcome.blocked => clearance.note == null
            ? 'Settle at the cashier, or ask the office for a promissory note.'
            : 'An approved note covers part of it. '
                '${_currency.format(clearance.shortfall)} is still uncovered.',
      };
}
