import 'package:intl/intl.dart';

import '../../../faculty_portal/domain/entities/grade.dart';
import '../entities/report_period.dart';
import '../entities/report_table.dart';

final _count = NumberFormat.decimalPattern();
final _oneDecimal = NumberFormat('0.0');
final _percent = NumberFormat.decimalPercentPattern(decimalDigits: 1);

/// One band of the DepEd descriptor scale.
///
/// Not arbitrary thresholds: these are the descriptors on every Philippine
/// report card, and 75 is the passing mark. Inventing our own bands would
/// produce a report a principal has to translate before they can use it,
/// and translate again before anyone above them will accept it.
enum GradeBand {
  outstanding('Outstanding', 90, 'O'),
  verySatisfactory('Very Satisfactory', 85, 'VS'),
  satisfactory('Satisfactory', 80, 'S'),
  fairlySatisfactory('Fairly Satisfactory', 75, 'FS'),
  didNotMeet('Did Not Meet Expectations', 0, 'DNME');

  /// Inclusive lower bound, in percent.
  final double floor;
  final String label;
  final String shortLabel;

  const GradeBand(this.label, this.floor, this.shortLabel);

  static GradeBand of(double percentage) =>
      GradeBand.values.firstWhere((band) => percentage >= band.floor);
}

/// How a cohort is actually doing, by subject.
///
/// Averages alone hide the thing worth acting on. Two subjects both
/// averaging 83 are a different problem when one has everybody within
/// five marks of it and the other has a third of the class below 75, and
/// only the distribution tells them apart -- which is why the bands are
/// the report and the average is one column of it.
class GradeDistributionReport {
  const GradeDistributionReport._();

  static ReportTable build({
    required ReportPeriod period,
    required List<Grade> grades,
    String? term,
  }) {
    final groups = <String, _Group>{};
    final terms = <String>{};

    for (final grade in grades) {
      if (!period.contains(grade.submittedAt)) continue;
      terms.add(grade.term.trim());
      if (term != null && term.isNotEmpty && grade.term.trim() != term) continue;
      // A grade out of a zero maximum has no percentage to band -- it is
      // a coursework item somebody saved before setting the total.
      if (grade.maxScore <= 0) continue;

      final key = '${grade.subject.trim().toLowerCase()}|${grade.section.trim().toLowerCase()}';
      (groups[key] ??= _Group(grade.subject.trim(), grade.section.trim())).add(grade);
    }

    final ordered = groups.values.toList()
      ..sort((a, b) {
        final bySubject = a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
        return bySubject != 0 ? bySubject : a.section.compareTo(b.section);
      });

    final rows = <ReportRow>[];
    final totals = _Group('', '');
    for (final group in ordered) {
      rows.add(ReportRow([
        group.subject,
        group.section.isEmpty ? '(not set)' : group.section,
        _count.format(group.students.length),
        _count.format(group.marks),
        _oneDecimal.format(group.average),
        for (final band in GradeBand.values) _count.format(group.bands[band] ?? 0),
        group.passRateLabel,
      ]));
      totals.absorb(group);
    }

    if (rows.isNotEmpty) {
      rows.add(ReportRow([
        'All subjects',
        '',
        _count.format(totals.students.length),
        _count.format(totals.marks),
        _oneDecimal.format(totals.average),
        for (final band in GradeBand.values) _count.format(totals.bands[band] ?? 0),
        totals.passRateLabel,
      ], isTotal: true));
    }

    final belowPassing = totals.bands[GradeBand.didNotMeet] ?? 0;

    return ReportTable(
      title: 'Grade Distribution by Subject',
      subtitle: term == null || term.isEmpty
          ? '${period.label} - all terms'
          : '${period.label} - $term',
      headline: [
        ReportStat(
          label: 'Average',
          value: totals.marks == 0 ? '-' : _oneDecimal.format(totals.average),
          caption: '${_count.format(totals.marks)} marks recorded',
        ),
        ReportStat(
          label: 'At or above 75',
          value: totals.passRateLabel,
          caption: belowPassing == 0
              ? null
              : '${_count.format(belowPassing)} below the passing mark',
        ),
        ReportStat(
          label: 'Subjects',
          value: _count.format(ordered.map((g) => g.subject.toLowerCase()).toSet().length),
          caption: '${_count.format(ordered.length)} subject-section pairs',
        ),
      ],
      columns: [
        const ReportColumn('Subject'),
        const ReportColumn('Section'),
        const ReportColumn('Students', numeric: true),
        const ReportColumn('Marks', numeric: true),
        const ReportColumn('Average %', numeric: true),
        for (final band in GradeBand.values)
          ReportColumn('${band.shortLabel} (${_bandRange(band)})', numeric: true),
        const ReportColumn('At or above 75', numeric: true),
      ],
      rows: rows,
      filterLabel: 'Term',
      filterOptions: (terms.where((t) => t.isNotEmpty).toList()..sort()),
      note: _note(terms, term),
    );
  }

  static String _bandRange(GradeBand band) => switch (band) {
        GradeBand.outstanding => '90+',
        GradeBand.verySatisfactory => '85-89',
        GradeBand.satisfactory => '80-84',
        GradeBand.fairlySatisfactory => '75-79',
        GradeBand.didNotMeet => 'below 75',
      };

  static String _note(Set<String> terms, String? term) {
    final parts = <String>[
      'Bands follow the DepEd descriptors: Outstanding 90 and above, Very '
          'Satisfactory 85-89, Satisfactory 80-84, Fairly Satisfactory 75-79, '
          'Did Not Meet Expectations below 75.',
      // Every recorded mark is one row here, so a subject that graded six
      // quizzes weighs six times a subject that graded one. Anybody
      // reading this as a final standing would be reading it wrong.
      'Every recorded mark counts once, including quizzes and assignments. '
          'These are not computed final grades, and a subject that records more '
          'coursework carries more weight in the average than one that records '
          'less.',
    ];
    if ((term == null || term.isEmpty) && terms.length > 1) {
      final sorted = terms.where((t) => t.isNotEmpty).toList()..sort();
      parts.add(
        'Marks from ${sorted.length} terms (${sorted.join(', ')}) are pooled. '
        'Pick a term to separate them.',
      );
    }
    return parts.join(' ');
  }
}

class _Group {
  final String subject;
  final String section;
  final Set<String> students = {};
  final Map<GradeBand, int> bands = {};
  int marks = 0;
  double _percentageTotal = 0;

  _Group(this.subject, this.section);

  double get average => marks == 0 ? 0 : _percentageTotal / marks;

  String get passRateLabel {
    final counted = marks;
    if (counted == 0) return '-';
    final passing = counted - (bands[GradeBand.didNotMeet] ?? 0);
    return _percent.format(passing / counted);
  }

  void add(Grade grade) {
    marks++;
    students.add(grade.studentId);
    _percentageTotal += grade.percentage;
    final band = GradeBand.of(grade.percentage);
    bands[band] = (bands[band] ?? 0) + 1;
  }

  void absorb(_Group other) {
    students.addAll(other.students);
    marks += other.marks;
    _percentageTotal += other._percentageTotal;
    for (final entry in other.bands.entries) {
      bands[entry.key] = (bands[entry.key] ?? 0) + entry.value;
    }
  }
}
