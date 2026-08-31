import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/discount.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _percent = NumberFormat.decimalPercentPattern(decimalDigits: 1);

/// What the school gave away, and to whom.
///
/// The question a private school's board asks every year and the system
/// could not answer, because until now a waiver was free text in a
/// remarks box. A discount that cannot be summed is a discount nobody
/// governs: the sibling policy grows, the board grants pile up, and the
/// first time anyone sees the total is when the year's collections come
/// in short.
///
/// Grouped by kind rather than by student, because the decision this
/// informs is a policy one -- "is the sibling discount costing us more
/// than it brings in" -- and a list of two hundred families does not
/// answer it. The count of families is beside each figure so a large
/// total from three board grants is not mistaken for a broad policy.
class DiscountsReport {
  const DiscountsReport._();

  static ReportTable build({
    required ReportPeriod period,
    required List<StudentSummary> students,
    required List<Assessment> assessments,
  }) {
    final divisionOf = {for (final s in students) s.id: s.educationLevel};

    final byKind = <DiscountKind, _Bucket>{};
    final byDivision = <EducationLevel, double>{};
    final familiesTouched = <String>{};
    var granted = 0.0;
    var grossAssessed = 0.0;

    for (final assessment in assessments) {
      // A voided assessment granted nothing in the end. Counting its
      // discounts would report money the school never gave away.
      if (assessment.isVoided) continue;
      if (!period.contains(assessment.assessedAt)) continue;

      grossAssessed += assessment.grossTotal;
      if (assessment.discounts.isEmpty) continue;

      familiesTouched.add(assessment.studentId);
      final division = divisionOf[assessment.studentId];

      for (final discount in assessment.discounts) {
        granted += discount.amount;
        final bucket = byKind[discount.kind] ??= _Bucket();
        bucket.amount += discount.amount;
        bucket.students.add(assessment.studentId);
        if (division != null) {
          byDivision[division] = (byDivision[division] ?? 0) + discount.amount;
        }
      }
    }

    final kinds = byKind.keys.toList()
      ..sort((a, b) => byKind[b]!.amount.compareTo(byKind[a]!.amount));

    final rows = <ReportRow>[
      for (final kind in kinds)
        ReportRow([
          kind.displayLabel,
          '${byKind[kind]!.students.length}',
          _peso.format(byKind[kind]!.amount),
          grossAssessed <= 0
              ? '--'
              : _percent.format(byKind[kind]!.amount / grossAssessed),
        ]),
      if (kinds.isNotEmpty)
        ReportRow(
          [
            'Total',
            '${familiesTouched.length}',
            _peso.format(granted),
            grossAssessed <= 0 ? '--' : _percent.format(granted / grossAssessed),
          ],
          isTotal: true,
        ),
    ];

    return ReportTable(
      title: 'Discounts and Scholarships',
      subtitle: period.label,
      columns: const [
        ReportColumn('Kind'),
        ReportColumn('Students', numeric: true),
        ReportColumn('Given', numeric: true),
        ReportColumn('Of fees assessed', numeric: true),
      ],
      rows: rows,
      headline: [
        ReportStat(
          label: 'Given away',
          value: _peso.format(granted),
          caption: grossAssessed <= 0
              ? null
              : 'of ${_peso.format(grossAssessed)} assessed',
        ),
        ReportStat(
          label: 'Students helped',
          value: '${familiesTouched.length}',
          caption: kinds.isEmpty ? 'None this period' : 'across ${kinds.length} '
              '${kinds.length == 1 ? 'kind' : 'kinds'}',
        ),
        if (byDivision.isNotEmpty)
          ReportStat(
            label: 'Most of it',
            value: _mostBy(byDivision).displayLabel,
            caption: _peso.format(byDivision[_mostBy(byDivision)]!),
          ),
      ],
      note: 'Counts discounts on assessments made in this period, so a '
          'scholarship granted last year does not reappear in this one. Voided '
          'assessments are excluded -- they granted nothing in the end. "Of '
          'fees assessed" is against the published fees before discounts, '
          'which is the figure the school would have billed had it granted '
          'none.',
    );
  }

  static EducationLevel _mostBy(Map<EducationLevel, double> byDivision) {
    final entries = byDivision.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class _Bucket {
  double amount = 0;

  /// A set, not a count: one family granted both a sibling discount and
  /// early payment must not be counted twice under the same kind.
  final Set<String> students = {};
}
