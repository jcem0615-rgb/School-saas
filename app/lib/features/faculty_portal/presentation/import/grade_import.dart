import '../../../../core/data_transfer/csv.dart' show ImportIssue;
import '../../../../core/data_transfer/sheet_values.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/grade.dart';

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
    final scoreText = row[2].trim();
    final maxScoreText = row[3].trim();
    final remarks = row[4].trim();

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
    // document every time -- so an import that ran twice would leave two
    // marks for one term and no way to tell which the teacher meant.
    if (existing.any((g) =>
        g.studentId == student.id && g.term.toLowerCase() == term.toLowerCase())) {
      return ImportIssue(
        rowNumber,
        '${student.fullName} already has a $term mark for this class.',
      );
    }
    if (!seen.add('${student.id}|${term.toLowerCase()}')) {
      return ImportIssue(
        rowNumber,
        '${student.fullName} appears twice for $term in this file.',
      );
    }

    return GradeImportRow(
      studentId: student.id,
      studentName: student.fullName,
      term: term,
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
  final double score;
  final double maxScore;
  final String? remarks;

  const GradeImportRow({
    required this.studentId,
    required this.studentName,
    required this.term,
    required this.score,
    required this.maxScore,
    required this.remarks,
  });
}
