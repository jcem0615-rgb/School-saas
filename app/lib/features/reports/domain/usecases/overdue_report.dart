import 'package:intl/intl.dart';

import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/installment.dart';
import '../../../payments/domain/entities/payment.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dueFormat = DateFormat('d MMM y');

/// Who is behind on their payment plan, and by how much.
///
/// The number a private school's administrator looks at every morning,
/// and the one the system could not produce before instalments existed.
/// A balance answers "how much is left to pay this year"; it says nothing
/// about whether any of it was due yet. A family on a four-payment plan
/// who has paid the first two is ₱22,000 short and perfectly current,
/// and chasing them is how a school loses a family it was never at risk
/// of losing.
///
/// Banded the way a collections meeting talks: 1-30 days, 31-60, 61-90,
/// over 90. The bands are on the *oldest* unpaid instalment, because
/// that is what makes a case old -- a family three months behind who
/// made a small payment last week has not become a new problem.
class OverdueReport {
  const OverdueReport._();

  static ReportTable build({
    required List<StudentSummary> students,
    required List<Payment> payments,
    required List<Assessment> assessments,
    /// Injectable so a report reads the same in a test as it did the day
    /// it was written. Everything here is relative to a date.
    DateTime? asOf,
  }) {
    final today = asOf ?? DateTime.now();

    final assessmentsByStudent = <String, List<Assessment>>{};
    for (final assessment in assessments) {
      (assessmentsByStudent[assessment.studentId] ??= []).add(assessment);
    }
    final paidByStudent = <String, double>{};
    for (final payment in payments) {
      paidByStudent[payment.studentId] =
          (paidByStudent[payment.studentId] ?? 0) + payment.amount;
    }

    final behind = <_Behind>[];
    var totalOverdue = 0.0;
    var onPlan = 0;

    for (final student in students) {
      final theirs = assessmentsByStudent[student.id] ?? const <Assessment>[];
      if (theirs.isEmpty) continue;

      final schedule = Assessment.combinedSchedule(theirs);
      if (schedule.isEmpty) continue;
      onPlan++;

      final paid = paidByStudent[student.id] ?? 0;
      final overdue = schedule.overdueAmount(paid: paid, asOf: today);
      if (overdue <= 0) continue;

      final oldest = schedule
          .standing(paid: paid, asOf: today)
          .where((line) => line.state == InstallmentState.overdue)
          .toList();
      // Cannot be empty: money is overdue, so some line is past its date
      // and unsettled. Guarded anyway rather than indexing blind -- a
      // crash on the collections screen is not the place to find out.
      if (oldest.isEmpty) continue;
      final worst = oldest.first;

      totalOverdue += overdue;
      behind.add(_Behind(student, worst, overdue));
    }

    // Sorted by how late, not by how much: a small debt six months old is
    // a different conversation from a large one due last week, and it is
    // the old one that stops being collectable.
    behind.sort((a, b) => b.worst.daysLate.compareTo(a.worst.daysLate));

    final rows = [
      for (final row in behind)
        ReportRow([
          row.student.fullName,
          row.student.studentNumber,
          row.student.classLabel,
          row.worst.installment.label,
          _dueFormat.format(row.worst.installment.dueDate),
          '${row.worst.daysLate}',
          _band(row.worst.daysLate),
          _peso.format(row.overdue),
        ]),
      if (behind.isNotEmpty)
        ReportRow(
          ['Total', '', '', '', '', '', '', _peso.format(totalOverdue)],
          isTotal: true,
        ),
    ];

    return ReportTable(
      title: 'Overdue Accounts',
      subtitle: 'As of ${_dueFormat.format(today)}',
      columns: const [
        ReportColumn('Student'),
        ReportColumn('Student No.'),
        ReportColumn('Class'),
        ReportColumn('Oldest unpaid'),
        ReportColumn('Was due'),
        ReportColumn('Days', numeric: true),
        ReportColumn('Age'),
        ReportColumn('Overdue', numeric: true),
      ],
      rows: rows,
      headline: [
        ReportStat(
          label: 'Overdue',
          value: _peso.format(totalOverdue),
          caption: behind.isEmpty ? 'Nobody is behind' : 'across ${behind.length} '
              '${behind.length == 1 ? 'family' : 'families'}',
        ),
        ReportStat(
          label: 'Families behind',
          value: '${behind.length}',
          caption: 'of $onPlan on a payment plan',
        ),
        if (behind.isNotEmpty)
          ReportStat(
            label: 'Oldest',
            value: '${behind.first.worst.daysLate} days',
            caption: behind.first.student.fullName,
          ),
      ],
      note: _note(onPlan: onPlan, studentCount: students.length),
    );
  }

  static String _band(int daysLate) => switch (daysLate) {
        <= 30 => '1-30 days',
        <= 60 => '31-60 days',
        <= 90 => '61-90 days',
        _ => 'Over 90 days',
      };

  /// Says what the report cannot see, because a collections list that
  /// looks complete and is not will be trusted and should not be.
  static String _note({required int onPlan, required int studentCount}) {
    final without = studentCount - onPlan;
    final base = 'Overdue is what the payment plan says should have arrived by '
        'today, less everything received. Payments are not tied to a '
        'particular instalment, so a family who paid ahead is not counted as '
        'behind on the next one.';
    if (without <= 0) return base;
    return '$base $without ${without == 1 ? 'student is' : 'students are'} not on '
        'a payment plan and cannot appear here at all -- their fees fell due '
        'when they were charged. Publish a plan on the fee schedule to bring '
        'them in.';
  }
}


/// One family's position, before it becomes a row.
class _Behind {
  final StudentSummary student;
  final InstallmentStanding worst;
  final double overdue;

  const _Behind(this.student, this.worst, this.overdue);
}
