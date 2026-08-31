import '../../../../core/errors/result.dart';
import '../entities/report_kind.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';
import '../repositories/reports_repository.dart';
import 'attendance_report.dart';
import 'collections_report.dart';
import 'enrollment_report.dart';
import 'grade_distribution_report.dart';
import 'discounts_report.dart';
import 'exam_permits_report.dart';
import 'overdue_report.dart';
import 'subsidy_claims_report.dart';

/// Fetches what a report needs and hands back the finished table.
///
/// The builders themselves are pure and take lists, which is what makes
/// them testable without a database; this is the one place that knows
/// which builder goes with which read.
class BuildReportUseCase {
  final ReportsRepository _repository;
  const BuildReportUseCase(this._repository);

  Future<Result<ReportTable>> call({
    required ReportKind kind,
    required ReportPeriod period,
    String? term,
  }) async {
    final fetched = await _repository.fetch(kind: kind, period: period);
    return switch (fetched) {
      Error(:final failure) => Error(failure),
      Success(:final value) => Success(_withTruncationNote(
          switch (kind) {
            ReportKind.enrollment => EnrollmentReport.build(value.students),
            ReportKind.collections => CollectionsReport.build(
                period: period,
                students: value.students,
                payments: value.payments,
                assessments: value.assessments,
              ),
            ReportKind.overdue => OverdueReport.build(
                students: value.students,
                payments: value.payments,
                assessments: value.assessments,
              ),
            ReportKind.discounts => DiscountsReport.build(
                period: period,
                students: value.students,
                assessments: value.assessments,
              ),
            ReportKind.subsidyClaims => SubsidyClaimsReport.build(
                period: period,
                students: value.students,
                assessments: value.assessments,
              ),
            ReportKind.examPermits => ExamPermitsReport.build(
                students: value.students,
                payments: value.payments,
                assessments: value.assessments,
                approvals: value.approvals,
              ),
            ReportKind.attendance => AttendanceReport.build(
                period: period,
                students: value.students,
                records: value.attendance,
              ),
            ReportKind.grades => GradeDistributionReport.build(
                period: period,
                grades: value.grades,
                term: term,
              ),
          },
          value.truncated,
        )),
    };
  }

  /// Puts the ceiling warning at the front of the note, where it cannot
  /// be missed, rather than appending it to a paragraph of caveats.
  static ReportTable _withTruncationNote(ReportTable table, Set<String> truncated) {
    if (truncated.isEmpty) return table;
    final what = truncated.toList()..sort();
    final warning = 'INCOMPLETE: this report hit the read limit on '
        '${what.join(', ')}. Figures below are computed from part of the data '
        'only. Narrow the date range and run it again.';
    return ReportTable(
      title: table.title,
      subtitle: table.subtitle,
      columns: table.columns,
      rows: table.rows,
      headline: table.headline,
      filterLabel: table.filterLabel,
      filterOptions: table.filterOptions,
      note: table.note == null ? warning : '$warning ${table.note}',
    );
  }
}
