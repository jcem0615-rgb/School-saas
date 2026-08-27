import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';

final _count = NumberFormat.decimalPattern();
final _percent = NumberFormat.decimalPercentPattern(decimalDigits: 1);

/// How often students actually turned up, by section.
///
/// By section rather than by division, because that is the unit anyone
/// can act on. A division running at 94% tells a principal nothing they
/// can do anything about; one section at 78% inside it tells them which
/// adviser to talk to this week.
///
/// The rate is present-and-late over all records, not present over all.
/// A late student came to school. Counting them against the rate makes
/// the figure measure punctuality while calling itself attendance, and
/// the two want different responses -- so lateness gets its own column
/// instead.
class AttendanceReport {
  const AttendanceReport._();

  static ReportTable build({
    required ReportPeriod period,
    required List<StudentSummary> students,
    required List<AttendanceRecord> records,
  }) {
    final byStudent = {for (final s in students) s.id: s};

    final groups = <String, _Group>{};
    var unmatched = 0;

    for (final record in records) {
      if (record.subjectType != AttendanceSubjectType.student) continue;
      final day = DateTime.tryParse(record.date);
      if (day == null || !period.contains(day)) continue;

      final student = byStudent[record.personId];
      if (student == null) {
        // A scan against a record this reader cannot see, or one since
        // deleted. Counted and reported rather than dropped: a rate
        // computed over an unknown fraction of the scans is not a rate.
        unmatched++;
        continue;
      }
      final key = '${student.educationLevel.index}|${student.gradeLevel.trim()}'
          '|${student.section.trim()}';
      (groups[key] ??= _Group(student.educationLevel, student.gradeLevel.trim(),
              student.section.trim()))
          .add(record);
    }

    final ordered = groups.values.toList()
      ..sort((a, b) {
        final byLevel = a.level.index.compareTo(b.level.index);
        if (byLevel != 0) return byLevel;
        final byGrade = a.gradeLevel.compareTo(b.gradeLevel);
        return byGrade != 0 ? byGrade : a.section.compareTo(b.section);
      });

    final rows = <ReportRow>[];
    final totals = _Group(EducationLevel.elementary, '', '');
    for (final group in ordered) {
      rows.add(ReportRow([
        group.level.displayLabel,
        group.gradeLevel.isEmpty ? '(not set)' : group.gradeLevel,
        group.section.isEmpty ? '(not set)' : group.section,
        _count.format(group.days.length),
        _count.format(group.records),
        _count.format(group.present),
        _count.format(group.late),
        _count.format(group.absent),
        _count.format(group.excused),
        group.rateLabel,
      ]));
      totals.absorb(group);
    }

    if (rows.isNotEmpty) {
      rows.add(ReportRow([
        'All sections',
        '',
        '',
        _count.format(totals.days.length),
        _count.format(totals.records),
        _count.format(totals.present),
        _count.format(totals.late),
        _count.format(totals.absent),
        _count.format(totals.excused),
        totals.rateLabel,
      ], isTotal: true));
    }

    return ReportTable(
      title: 'Attendance Rate by Section',
      subtitle: period.label,
      headline: [
        ReportStat(
          label: 'Attendance rate',
          value: totals.rateLabel,
          caption: 'present or late; excused absences excluded',
        ),
        ReportStat(
          label: 'Late arrivals',
          value: _count.format(totals.late),
          caption: totals.records == 0
              ? null
              : '${_percent.format(totals.late / totals.records)} of records',
        ),
        ReportStat(
          label: 'Days recorded',
          value: _count.format(totals.days.length),
          caption: 'of ${period.dayCount} in the period',
        ),
      ],
      columns: const [
        ReportColumn('Division'),
        ReportColumn('Grade Level'),
        ReportColumn('Section'),
        ReportColumn('Days', numeric: true),
        ReportColumn('Records', numeric: true),
        ReportColumn('Present', numeric: true),
        ReportColumn('Late', numeric: true),
        ReportColumn('Absent', numeric: true),
        ReportColumn('Excused', numeric: true),
        ReportColumn('Rate', numeric: true),
      ],
      rows: rows,
      note: _note(period, totals, unmatched),
    );
  }

  static String _note(ReportPeriod period, _Group totals, int unmatched) {
    final parts = <String>[
      'The rate counts present and late together, against present, late and '
          'absent. Lateness is reported separately rather than deducted from '
          'it -- a late student came to school.',
      'Excused absences are left out of the rate on both sides. A student with '
          'a medical certificate is not a truant, and counting them as one is '
          'how a section with an outbreak ends up reading as a discipline '
          'problem.',
      'Days counts the dates attendance was actually taken, not the school '
          'calendar -- a day nobody scanned does not appear here at all, so a '
          'section with fewer days than the rest may be a recording gap rather '
          'than a holiday.',
    ];
    if (unmatched > 0) {
      parts.add(
        '$unmatched ${unmatched == 1 ? 'record is' : 'records are'} excluded: '
        'the student record they point at is not among those visible here.',
      );
    }
    return parts.join(' ');
  }
}

class _Group {
  final EducationLevel level;
  final String gradeLevel;
  final String section;
  final Set<String> days = {};
  int records = 0;
  int present = 0;
  int late = 0;
  int absent = 0;
  int excused = 0;

  _Group(this.level, this.gradeLevel, this.section);

  /// Excused absences sit outside the rate entirely -- neither in the
  /// numerator nor the denominator. A student with a medical certificate
  /// is not a truant, and counting them as one is how a section with an
  /// outbreak ends up looking like a discipline problem.
  String get rateLabel {
    final counted = present + late + absent;
    if (counted == 0) return '-';
    return _percent.format((present + late) / counted);
  }

  void add(AttendanceRecord record) {
    records++;
    days.add(record.date);
    switch (record.status) {
      case AttendanceStatus.present:
        present++;
      case AttendanceStatus.late:
        late++;
      case AttendanceStatus.absent:
        absent++;
      case AttendanceStatus.excused:
        excused++;
    }
  }

  void absorb(_Group other) {
    days.addAll(other.days);
    records += other.records;
    present += other.present;
    late += other.late;
    absent += other.absent;
    excused += other.excused;
  }
}
