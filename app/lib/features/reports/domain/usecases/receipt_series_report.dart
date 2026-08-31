import 'package:intl/intl.dart';

import '../../../payments/domain/entities/payment.dart';
import '../../../payments/domain/entities/receipt_booklet.dart';
import '../../../payments/domain/entities/receipt_series.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dayFormat = DateFormat('d MMM y');

/// Every official receipt number in the booklet, and what became of it.
///
/// A school can already list the receipts it issued. What it cannot do,
/// and what an examiner asks for, is account for the ones it did not: a
/// booklet of five hundred with four hundred and ninety issued and nine
/// cancelled has one number nobody can explain. Finding that in December
/// rather than the following October is the difference between a
/// correction and a finding.
///
/// Only the *active* booklet is reconciled. A closed booklet is history
/// and its reconciliation was done when it was closed; showing all of
/// them at once would bury the one still in use under two thousand rows.
class ReceiptSeriesReport {
  const ReceiptSeriesReport._();

  static ReportTable build({
    required List<StudentSummary> students,
    required List<Payment> payments,
    required List<ReceiptBooklet> booklets,
  }) {
    final active = booklets.where((b) => b.isActive).toList();

    if (active.isEmpty) {
      return const ReportTable(
        title: 'Receipt Series',
        subtitle: 'No booklet registered',
        columns: [ReportColumn('Receipt')],
        rows: [],
        note: 'This school has not registered a receipt booklet, so there is '
            'no series to reconcile. Register the booklet under Payment '
            'Settings -- its range, and the Authority to Print number on the '
            'cover -- and every receipt recorded afterwards is checked '
            'against it.',
      );
    }
    if (active.length > 1) {
      return ReportTable(
        title: 'Receipt Series',
        subtitle: '${active.length} booklets marked active',
        columns: const [ReportColumn('Booklet')],
        rows: [for (final b in active) ReportRow([b.rangeLabel])],
        note: 'More than one booklet is marked active, so which series a '
            'receipt belongs to is ambiguous and no reconciliation can be '
            'trusted. Close the one that is finished.',
      );
    }

    final booklet = active.single;
    final nameOf = {for (final s in students) s.id: s.fullName};

    final series = reconcileSeries(booklet: booklet, payments: payments);

    // Only as far as the highest number used. The rest of the booklet is
    // blank paper in a drawer, and five hundred rows of "unaccounted"
    // would drown the handful that are actually a question.
    final used = series.highestUsed;
    final shown = used == null
        ? <ReceiptSeriesEntry>[]
        : series.entries.where((e) => e.number <= used).toList();

    final rows = <ReportRow>[
      for (final entry in shown)
        ReportRow([
          entry.formatted,
          entry.status.displayLabel,
          entry.issuedAt == null ? '--' : _dayFormat.format(entry.issuedAt!),
          entry.studentId == null
              ? (entry.cancelReason ?? '--')
              : (nameOf[entry.studentId] ?? 'Unknown student'),
          entry.collectedByName ?? '--',
          entry.amount == null ? '--' : _peso.format(entry.amount),
        ]),
      if (shown.isNotEmpty)
        ReportRow(
          ['Total', '', '', '', '', _peso.format(series.collected)],
          isTotal: true,
        ),
    ];

    final gaps = series.gapLabels;

    return ReportTable(
      title: 'Receipt Series',
      subtitle: '${booklet.rangeLabel}'
          '${booklet.atpNumber == null ? '' : ' · ATP ${booklet.atpNumber}'}',
      columns: const [
        ReportColumn('Receipt'),
        ReportColumn('Status'),
        ReportColumn('Date'),
        ReportColumn('Issued to / reason'),
        ReportColumn('Collected by'),
        ReportColumn('Amount', numeric: true),
      ],
      rows: rows,
      headline: [
        // Unaccounted first, and always shown even at zero. A figure that
        // disappears when it is fine is one nobody learns to look for.
        ReportStat(
          label: 'Unaccounted',
          value: '${gaps.isEmpty ? 0 : series.unaccounted.where((e) => e.number <= (used ?? 0)).length}',
          caption: gaps.isEmpty ? 'Series is complete' : gaps.join(', '),
        ),
        ReportStat(
          label: 'Issued',
          value: '${series.issued.length}',
          caption: 'collecting ${_peso.format(series.collected)}',
        ),
        ReportStat(
          label: 'Next expected',
          value: series.nextExpected == null
              ? 'Booklet full'
              : booklet.format(series.nextExpected!),
          caption: series.nextExpected == null
              ? 'Register the next booklet'
              : '${booklet.lastNumber - (used ?? booklet.firstNumber - 1)} left',
        ),
      ],
      note: 'Numbers above the highest one used are blank paper and are not '
          'listed. A gap *inside* what has been used is the question: it is a '
          'receipt that was written and not recorded, or one recorded against '
          'a booklet that is not this one. Refunds do not consume a number '
          'here -- the school issues its own document for those.',
    );
  }
}
