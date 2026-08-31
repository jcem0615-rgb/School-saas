import 'package:intl/intl.dart';

import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/subsidy.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// What the school can bill DepEd for, line by line.
///
/// This is the report that replaces a spreadsheet. A private school
/// running ESC keeps a parallel ledger in Excel -- every grantee, their
/// certificate number, the amount -- because the billing to PEAC needs a
/// list and no school system produced one. Reconciling that spreadsheet
/// against the actual enrolment is where the money gets lost: a student
/// who transferred out in September is still on the claim, or a grantee
/// enrolled in July never made it onto it.
///
/// Here the list *is* the enrolment: every line comes from an assessment
/// that actually charged a student, so it cannot include somebody who was
/// never assessed, and it cannot omit somebody who was.
///
/// One row per grant rather than per student, because the school bills
/// per certificate: a student holding both an ESC grant and a city
/// scholarship is two claims to two grantors.
class SubsidyClaimsReport {
  const SubsidyClaimsReport._();

  static ReportTable build({
    required ReportPeriod period,
    required List<StudentSummary> students,
    required List<Assessment> assessments,
  }) {
    final studentsById = {for (final s in students) s.id: s};

    final claims = <_Claim>[];
    final byProgramme = <SubsidyProgramme, double>{};
    final grantees = <String>{};
    var total = 0.0;

    for (final assessment in assessments) {
      // A voided assessment charged nothing, so there is nothing to
      // claim against it. Billing PEAC for a grant on a reversed
      // assessment is the kind of error that gets a school audited.
      if (assessment.isVoided) continue;
      if (!period.contains(assessment.assessedAt)) continue;
      if (assessment.subsidies.isEmpty) continue;

      final student = studentsById[assessment.studentId];
      for (final subsidy in assessment.subsidies) {
        claims.add(_Claim(assessment, subsidy, student));
        total += subsidy.amount;
        byProgramme[subsidy.programme] =
            (byProgramme[subsidy.programme] ?? 0) + subsidy.amount;
        grantees.add(assessment.studentId);
      }
    }

    // By programme, then by student name: the billing form is filled in
    // one programme at a time, and inside it a list in name order is the
    // one a person can check against their own paperwork.
    claims.sort((a, b) {
      final byProg = a.subsidy.programme.index.compareTo(b.subsidy.programme.index);
      if (byProg != 0) return byProg;
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });

    final rows = <ReportRow>[
      for (final claim in claims)
        ReportRow([
          claim.subsidy.programme.displayLabel,
          claim.studentName,
          claim.student?.studentNumber ?? '--',
          claim.student?.classLabel ?? '--',
          claim.subsidy.referenceNumber,
          claim.assessment.schoolYear,
          _peso.format(claim.subsidy.amount),
        ]),
      if (claims.isNotEmpty)
        ReportRow(
          ['Total', '', '', '', '', '', _peso.format(total)],
          isTotal: true,
        ),
    ];

    return ReportTable(
      title: 'ESC and Voucher Claims',
      subtitle: period.label,
      columns: const [
        ReportColumn('Programme'),
        ReportColumn('Student'),
        ReportColumn('Student No.'),
        ReportColumn('Class'),
        ReportColumn('Certificate / QVR'),
        ReportColumn('School year'),
        ReportColumn('Claimable', numeric: true),
      ],
      rows: rows,
      headline: [
        ReportStat(
          label: 'Claimable',
          value: _peso.format(total),
          caption: claims.isEmpty
              ? 'No subsidies recorded this period'
              : '${claims.length} ${claims.length == 1 ? 'claim' : 'claims'}',
        ),
        ReportStat(
          label: 'Grantees',
          value: '${grantees.length}',
          caption: 'students receiving a grant',
        ),
        for (final entry in _ranked(byProgramme).take(1))
          ReportStat(
            label: entry.key.displayLabel,
            value: _peso.format(entry.value),
            caption: 'largest programme',
          ),
      ],
      note: 'What the school may bill against, taken from the assessments '
          'themselves, so a grantee who was never assessed cannot appear and '
          'one who was cannot be left off. Voided assessments are excluded. '
          'This is the claim, not the receipt: whether a grant has actually '
          'been paid is not tracked here.',
    );
  }

  static List<MapEntry<SubsidyProgramme, double>> _ranked(
      Map<SubsidyProgramme, double> byProgramme) {
    final entries = byProgramme.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}

/// One billable line, before it becomes a row.
class _Claim {
  final Assessment assessment;
  final Subsidy subsidy;
  final StudentSummary? student;

  const _Claim(this.assessment, this.subsidy, this.student);

  /// The assessment's own copy of the name, falling back to the live
  /// record. The assessment's is the one that was true when the grant was
  /// recorded, which is the name on the certificate.
  String get studentName =>
      assessment.studentName.isNotEmpty ? assessment.studentName : (student?.fullName ?? 'Unknown');
}
