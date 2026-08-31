import '../../../../core/data_transfer/csv.dart' show ImportIssue;
import '../../../../core/data_transfer/sheet_values.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/grade.dart';
import '../../domain/entities/grading_scheme.dart';

/// Turns spreadsheet rows into marks the teacher could have typed.
///
/// Import was refused here once, on the grounds that it would have to
/// resolve student names to ids and re-run the per-student scope check
/// firestore.rules applies. The first half is true and is exactly what
/// this file does -- against the section roster the screen already
/// loads, so a name that is not in the class is refused rather than
/// guessed at. The second half was wrong: every row goes through the
/// same `submitGrade` the dialog uses, so the rules check runs per write
/// exactly as it always did and nothing is bypassed.
///
/// Subject and section are not columns. The teacher has already chosen
/// them on the screen, and a file that could name a different section
/// would be a way of posting marks to a class the roster check was never
/// run against.
class GradeImport {
  GradeImport._();

  /// The mark a spreadsheet leaves out most often, and the one the
  /// submit dialog already defaults to.
  static const defaultMaxScore = 100.0;

  /// Reads the component column: "written work", "WW", "performance
  /// task", "PT", "quarterly assessment", "QA". Blank is written work,
  /// which is where a quiz or a seatwork belongs and is what every mark
  /// posted before components existed already counts as.
  ///
  /// Returns null for text that is none of these, so the row is refused
  /// rather than quietly weighted as something the teacher did not say.
  static GradingComponent? parseComponent(String text) {
    final needle = text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (needle.isEmpty) return GradingComponent.writtenWork;
    for (final component in GradingComponent.values) {
      if (needle == component.shortLabel.toLowerCase()) return component;
      if (needle == component.displayLabel.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
        return component;
      }
      // "performance task" for "Performance Tasks", and the reverse.
      if (needle == component.value.replaceAll(RegExp(r'[^a-z]'), '')) return component;
    }
    if (needle == 'performancetask') return GradingComponent.performanceTask;
    if (needle == 'writtenworks') return GradingComponent.writtenWork;
    if (needle == 'quarterlyexam' || needle == 'quarterlyassessments') {
      return GradingComponent.quarterlyAssessment;
    }
    return null;
  }

  /// Validates one spreadsheet row into something submittable.
  ///
  /// [roster] is the class as it stands, [existing] the marks already
  /// posted for this subject and section, and [seen] carries the rows
  /// already accepted from this same file.
  static Object? parseRow({
    required List<String> row,
    required int rowNumber,
    required List<StudentSummary> roster,
    required List<Grade> existing,
    required Set<String> seen,
  }) {
    final studentText = row[0].trim();
    final term = row[1].trim();
    final componentText = row[2].trim();
    final scoreText = row[3].trim();
    final maxScoreText = row[4].trim();
    final remarks = row[5].trim();

    if (studentText.isEmpty) return ImportIssue(rowNumber, 'Student is required.');

    // Student number first: it is the one identifier that cannot be
    // ambiguous, and a school with two Maria Santos in one section is
    // not unusual enough to leave to chance.
    final byNumber = roster
        .where((s) => s.studentNumber.toLowerCase() == studentText.toLowerCase())
        .toList();
    final matches = byNumber.isNotEmpty
        ? byNumber
        : roster.where((s) => _sameName(s, studentText)).toList();

    if (matches.isEmpty) {
      return ImportIssue(
        rowNumber,
        '"$studentText" is not in this section. Check the spelling, or use '
        'their student number.',
      );
    }
    if (matches.length > 1) {
      return ImportIssue(
        rowNumber,
        'More than one student in this section is called "$studentText". '
        'Use their student number instead: '
        '${matches.map((s) => s.studentNumber).join(', ')}.',
      );
    }
    final student = matches.single;

    if (term.isEmpty) {
      return ImportIssue(rowNumber, 'Term is required (for example Q1).');
    }

    final component = parseComponent(componentText);
    if (component == null) {
      return ImportIssue(
        rowNumber,
        'Could not read the component "$componentText". Use Written Work, '
        'Performance Tasks or Quarterly Assessment (WW, PT, QA), or leave '
        'it blank for written work.',
      );
    }

    if (scoreText.isEmpty) return ImportIssue(rowNumber, 'Score is required.');
    final score = SheetValues.parseAmount(scoreText);
    if (score == null) {
      return ImportIssue(rowNumber, 'Could not read the score "$scoreText".');
    }
    if (score < 0) return ImportIssue(rowNumber, 'Score cannot be negative.');

    // Blank means the usual mark out of 100 -- the same default the
    // submit dialog offers -- because a column of 100s is the first
    // thing anyone preparing this file deletes.
    var maxScore = defaultMaxScore;
    if (maxScoreText.isNotEmpty) {
      final parsed = SheetValues.parseAmount(maxScoreText);
      if (parsed == null) {
        return ImportIssue(rowNumber, 'Could not read the max score "$maxScoreText".');
      }
      maxScore = parsed;
    }
    if (maxScore <= 0) {
      return ImportIssue(rowNumber, 'Max score must be more than zero.');
    }
    if (score > maxScore) {
      // Almost always a row where the two columns were filled in the
      // wrong order, and a mark over 100% would go into the average as
      // if it were real.
      return ImportIssue(
        rowNumber,
        'Score $scoreText is higher than the max score '
        '${maxScore.toStringAsFixed(0)}.',
      );
    }

    // A mark is posted, never replaced -- submitGrade writes a new
    // document every time -- and scores inside one component are summed,
    // so an import that ran twice would silently double a child's
    // written work.
    //
    // What counts as a duplicate had to widen when components arrived. A
    // student legitimately has many marks in one term now: three
    // components, and several pieces of work inside each. So the check is
    // no longer "already has a mark this term" -- which would refuse the
    // second quiz -- but "already has this exact mark": same component,
    // same label, same score out of the same total. That is a file being
    // run twice. Two genuinely identical unlabelled quizzes are the one
    // case this refuses wrongly, and naming one of them in Remarks is the
    // way through.
    final fingerprint = '${student.id}|${term.toLowerCase()}|${component.value}|'
        '${remarks.toLowerCase()}|$score|$maxScore';

    if (existing.any((g) =>
        g.studentId == student.id &&
        g.term.toLowerCase() == term.toLowerCase() &&
        g.component == component &&
        (g.remarks ?? '').toLowerCase() == remarks.toLowerCase() &&
        g.score == score &&
        g.maxScore == maxScore)) {
      return ImportIssue(
        rowNumber,
        '${student.fullName} already has this exact ${component.displayLabel} '
        'mark for $term. Posting it again would count it twice.',
      );
    }
    if (!seen.add(fingerprint)) {
      return ImportIssue(
        rowNumber,
        '${student.fullName} appears twice in this file with the same '
        '${component.displayLabel} mark for $term.',
      );
    }

    return GradeImportRow(
      studentId: student.id,
      studentName: student.fullName,
      term: term,
      component: component,
      score: score,
      maxScore: maxScore,
      remarks: remarks.isEmpty ? null : remarks,
    );
  }

  /// Matches "Maria Santos" and the "Santos, Maria" a class list is just
  /// as likely to be sorted as. Whitespace is collapsed because a name
  /// copied out of another system routinely carries a double space.
  static bool _sameName(StudentSummary s, String text) {
    final target = _normalise(text);
    if (_normalise(s.fullName) == target) return true;
    if (_normalise('${s.lastName}, ${s.firstName}') == target) return true;
    final middle = s.middleName;
    if (middle != null && middle.isNotEmpty) {
      if (_normalise('${s.firstName} $middle ${s.lastName}') == target) return true;
    }
    return false;
  }

  static String _normalise(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// One validated spreadsheet row, ready for `submitGrade`.
class GradeImportRow {
  final String studentId;
  final String studentName;
  final String term;
  final GradingComponent component;
  final double score;
  final double maxScore;
  final String? remarks;

  const GradeImportRow({
    required this.studentId,
    required this.studentName,
    required this.term,
    required this.component,
    required this.score,
    required this.maxScore,
    required this.remarks,
  });
}
