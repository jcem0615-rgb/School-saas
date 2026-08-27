import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_table.dart';

final _count = NumberFormat.decimalPattern();

/// Who is on the roll, by division and grade level.
///
/// The first report any school is asked for and the one it is asked for
/// most often: DepEd wants enrolment by level, the division office wants
/// it by grade, and the school itself wants to know which sections are
/// thin before it staffs them.
///
/// Every status gets a column rather than filtering to enrolled and
/// calling it the roll. A grade level showing four transferred-out
/// against thirty enrolled is the fact worth surfacing, and it vanishes
/// the moment the report shows only the survivors.
class EnrollmentReport {
  const EnrollmentReport._();

  static ReportTable build(List<StudentSummary> students) {
    final groups = <String, _Group>{};
    for (final student in students) {
      // Sorted by the division's own order, then grade level as typed --
      // "Grade 10" and "Grade 4" are free text in this system, so there
      // is no numeric sort to be had that would not mis-order a section
      // named "Kinder" or "1st Year".
      final key = '${student.educationLevel.index}|${student.gradeLevel.trim()}';
      (groups[key] ??= _Group(student.educationLevel, student.gradeLevel.trim()))
          .add(student);
    }

    final ordered = groups.values.toList()
      ..sort((a, b) {
        final byLevel = a.level.index.compareTo(b.level.index);
        return byLevel != 0 ? byLevel : a.gradeLevel.compareTo(b.gradeLevel);
      });

    final rows = <ReportRow>[];
    final totals = _Group(EducationLevel.elementary, '');
    for (final group in ordered) {
      rows.add(ReportRow([
        group.level.displayLabel,
        group.gradeLevel.isEmpty ? '(not set)' : group.gradeLevel,
        _count.format(group.sections.length),
        _count.format(group.enrolled),
        _count.format(group.inactive),
        _count.format(group.graduated),
        _count.format(group.transferredOut),
        _count.format(group.total),
      ]));
      totals.absorb(group);
    }

    if (rows.isNotEmpty) {
      rows.add(ReportRow([
        'All divisions',
        '',
        _count.format(totals.sections.length),
        _count.format(totals.enrolled),
        _count.format(totals.inactive),
        _count.format(totals.graduated),
        _count.format(totals.transferredOut),
        _count.format(totals.total),
      ], isTotal: true));
    }

    final divisions = ordered.map((g) => g.level).toSet().length;

    return ReportTable(
      title: 'Enrollment by Division',
      subtitle: 'As of today',
      headline: [
        ReportStat(
          label: 'Enrolled',
          value: _count.format(totals.enrolled),
          caption: 'across $divisions ${divisions == 1 ? 'division' : 'divisions'}',
        ),
        ReportStat(
          label: 'Sections',
          value: _count.format(totals.sections.length),
        ),
        ReportStat(
          label: 'On record',
          value: _count.format(totals.total),
          caption: 'every status, not only enrolled',
        ),
      ],
      columns: const [
        ReportColumn('Division'),
        ReportColumn('Grade Level'),
        ReportColumn('Sections', numeric: true),
        ReportColumn('Enrolled', numeric: true),
        ReportColumn('Inactive', numeric: true),
        ReportColumn('Graduated', numeric: true),
        ReportColumn('Transferred Out', numeric: true),
        ReportColumn('Total', numeric: true),
      ],
      rows: rows,
      // A head count taken today, not a snapshot of any past date: the
      // student record carries one status, and changing it overwrites
      // what was there. Anyone reconciling this against last term's
      // figures needs to know it moved.
      note: 'Counts reflect each student record as it stands today. A student '
          'who transferred out last term is counted as transferred out here, '
          'not as enrolled in the term they left.',
    );
  }
}

class _Group {
  final EducationLevel level;
  final String gradeLevel;
  final Set<String> sections = {};
  int enrolled = 0;
  int inactive = 0;
  int graduated = 0;
  int transferredOut = 0;

  _Group(this.level, this.gradeLevel);

  int get total => enrolled + inactive + graduated + transferredOut;

  void add(StudentSummary student) {
    final section = student.section.trim();
    if (section.isNotEmpty) sections.add('${level.index}|$gradeLevel|$section');
    switch (student.status) {
      case StudentStatus.enrolled:
        enrolled++;
      case StudentStatus.inactive:
        inactive++;
      case StudentStatus.graduated:
        graduated++;
      case StudentStatus.transferredOut:
        transferredOut++;
    }
  }

  void absorb(_Group other) {
    sections.addAll(other.sections);
    enrolled += other.enrolled;
    inactive += other.inactive;
    graduated += other.graduated;
    transferredOut += other.transferredOut;
  }
}
