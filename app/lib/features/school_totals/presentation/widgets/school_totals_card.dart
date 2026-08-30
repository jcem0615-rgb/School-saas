import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/school_totals.dart';
import '../controllers/school_totals_controller.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _count = NumberFormat.decimalPattern();

/// Enrolment and collections, on the dashboard of everyone who runs the
/// school.
///
/// The Owner has always had these numbers, because the platform bills on
/// the active-student count. Inside the school the same figures existed
/// only in a report somebody had to go and ask for -- which is not the
/// same as knowing, and is why a Director could not answer "how many are
/// we teaching, and how much are we owed" without leaving the screen they
/// start their day on.
class SchoolTotalsCard extends ConsumerWidget {
  const SchoolTotalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(schoolTotalsProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enrolment and collections',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(schoolTotalsProvider),
                ),
              ],
            ),
            const SizedBox(height: 4),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'These figures could not be read: $err',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              data: (totals) => _Figures(totals: totals),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figures extends StatelessWidget {
  final SchoolTotals totals;
  const _Figures({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totals.division != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              // Said out loud, because a head count that quietly covered
              // one division of four would read as the whole school.
              '${totals.division!.displayLabel} only - your assigned division.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        Wrap(
          spacing: 28,
          runSpacing: 14,
          children: [
            _Figure(
              value: _count.format(totals.activeStudents),
              label: 'Active students',
              emphasis: true,
            ),
            if (totals.includesMoney) ...[
              _Figure(
                value: _peso.format(totals.outstanding),
                label: totals.studentsOwing == 1
                    ? 'Outstanding, 1 student'
                    : 'Outstanding, ${_count.format(totals.studentsOwing ?? 0)} students',
              ),
              _Figure(
                value: _peso.format(totals.collectedThisMonth),
                label: 'Collected this month',
              ),
            ],
          ],
        ),
        if (!totals.includesMoney)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              // Not an omission to wonder about. Academic oversight and
              // the school's money are separate on purpose.
              'Fees and balances sit with the Director, Admin and Registrar.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;
  final bool emphasis;

  const _Figure({required this.value, required this.label, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasis ? theme.colorScheme.primary : theme.colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
