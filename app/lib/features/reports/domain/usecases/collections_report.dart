import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/payment.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _percent = NumberFormat.decimalPercentPattern(decimalDigits: 1);

/// What came in against what is still owed.
///
/// The one report a school board asks for by name, and the reason the
/// fee-assessment work had to land first: before assessments existed
/// there was no "assessed" figure to collect against, only a balance
/// somebody had typed, so a collection rate could not honestly be
/// computed at all.
///
/// Collected and assessed are both period figures. Outstanding is not --
/// it is the balance as it stands right now, because that is the only
/// form the system holds it in. Mixing a period figure and a running one
/// in the same table is defensible only if the table says so, which is
/// what the note is for.
class CollectionsReport {
  const CollectionsReport._();

  static ReportTable build({
    required ReportPeriod period,
    required List<StudentSummary> students,
    required List<Payment> payments,
    required List<Assessment> assessments,
  }) {
    final divisionOf = {for (final s in students) s.id: s.educationLevel};
    final groups = <EducationLevel, _Group>{};
    _Group groupFor(EducationLevel level) => groups[level] ??= _Group(level);

    for (final student in students) {
      final group = groupFor(student.educationLevel);
      group.students++;
      // A credit balance is money the school holds, not money it is
      // owed. Summing it into receivables would let one family's
      // overpayment quietly cancel another family's arrears and report
      // the pair as settled.
      if (student.balance > 0) {
        group.outstanding += student.balance;
        group.withBalance++;
      } else if (student.balance < 0) {
        group.credit += -student.balance;
      }
    }

    for (final payment in payments) {
      if (!period.contains(payment.createdAt)) continue;
      final level = divisionOf[payment.studentId];
      if (level == null) continue; // a payment against a record this reader cannot see
      // Every row as it stands: a refund is its own negative row and the
      // payment it reverses keeps its positive one, so the pair nets
      // itself out. Dropping either overstates or understates the take.
      groupFor(level).collected += payment.amount;
    }

    for (final assessment in assessments) {
      if (!period.contains(assessment.assessedAt)) continue;
      final level = divisionOf[assessment.studentId];
      if (level == null) continue;
      groupFor(level).assessed += assessment.effectiveTotal;
    }

    final ordered = groups.values.toList()
      ..sort((a, b) => a.level.index.compareTo(b.level.index));

    final rows = <ReportRow>[];
    final totals = _Group(EducationLevel.elementary);
    for (final group in ordered) {
      rows.add(ReportRow([
        group.level.displayLabel,
        '${group.students}',
        _peso.format(group.assessed),
        _peso.format(group.collected),
        _peso.format(group.outstanding),
        '${group.withBalance}',
        _rate(group.collected, group.assessed),
      ]));
      totals.absorb(group);
    }

    if (rows.isNotEmpty) {
      rows.add(ReportRow([
        'All divisions',
        '${totals.students}',
        _peso.format(totals.assessed),
        _peso.format(totals.collected),
        _peso.format(totals.outstanding),
        '${totals.withBalance}',
        _rate(totals.collected, totals.assessed),
      ], isTotal: true));
    }

    return ReportTable(
      title: 'Collections and Receivables',
      subtitle: period.label,
      headline: [
        ReportStat(
          label: 'Collected',
          value: _peso.format(totals.collected),
          caption: 'net of refunds, in this period',
        ),
        ReportStat(
          label: 'Outstanding',
          value: _peso.format(totals.outstanding),
          caption: '${totals.withBalance} '
              '${totals.withBalance == 1 ? 'student owes' : 'students owe'} money today',
        ),
        ReportStat(
          label: 'Assessed',
          value: _peso.format(totals.assessed),
          caption: 'charged in this period',
        ),
      ],
      columns: const [
        ReportColumn('Division'),
        ReportColumn('Students', numeric: true),
        ReportColumn('Assessed', numeric: true),
        ReportColumn('Collected', numeric: true),
        ReportColumn('Outstanding', numeric: true),
        ReportColumn('Owing', numeric: true),
        ReportColumn('Collected / Assessed', numeric: true),
      ],
      rows: rows,
      note: _note(totals),
    );
  }

  /// Deliberately not a single sentence. Three separate things about
  /// this table are easy to read wrongly, and each of them turns a
  /// figure into the wrong decision.
  static String _note(_Group totals) {
    final parts = <String>[
      'Assessed and Collected cover the selected period. Outstanding is the '
          'balance as it stands today, including anything charged before this '
          'period began -- so the last column is not a settlement rate for '
          'these students, only a ratio of the two period figures.',
      'Collected is net of refunds.',
    ];
    if (totals.credit > 0) {
      parts.add(
        'Credit balances totalling ${_peso.format(totals.credit)} are excluded '
        'from Outstanding: money the school is holding is not money it is owed.',
      );
    }
    return parts.join(' ');
  }

  static String _rate(double collected, double assessed) {
    if (assessed <= 0) return '-';
    return _percent.format(collected / assessed);
  }
}

class _Group {
  final EducationLevel level;
  int students = 0;
  int withBalance = 0;
  double collected = 0;
  double assessed = 0;
  double outstanding = 0;
  double credit = 0;

  _Group(this.level);

  void absorb(_Group other) {
    students += other.students;
    withBalance += other.withBalance;
    collected += other.collected;
    assessed += other.assessed;
    outstanding += other.outstanding;
    credit += other.credit;
  }
}
