import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/storage/pdf_image.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../domain/entities/document_release.dart';
import '../../domain/entities/student_summary.dart';

final _longDate = DateFormat('d MMMM y');

/// The mark at which a subject is passed in Philippine basic education.
const _passingRating = 75.0;

/// Builds the two documents a registrar's office is asked to account
/// for: the Transcript of Records and Form 137.
///
/// Both are printed from the marks the faculty portal holds, and both
/// say so on the page. That line matters more than it looks: a school
/// whose teachers have not finished encoding a quarter would otherwise
/// hand a parent a transcript that looks complete and is not, and the
/// registrar signing it has no way to tell from the sheet in front of
/// them. A document that names its own source can be checked.
///
/// These are the school's own records, laid out for the school's own
/// use. Neither is produced on a government form or claims to be one --
/// where a division office requires its own printed template, this is
/// what gets copied onto it.
///
/// Punctuation on the page is kept to ASCII. The PDF is drawn with the
/// built-in Helvetica, which has no glyph for an em dash or a peso sign
/// and drops them silently rather than failing -- so a dash somebody
/// typed here would simply be missing from the printed sheet, and
/// nobody would find out until a parent was holding it. Accented Latin
/// letters are fine, which is what matters: a name with an enye in it
/// prints correctly.
class AcademicRecordPdf {
  AcademicRecordPdf._();

  /// A reference the office can quote back.
  ///
  /// Built from the document, the student number and the date rather
  /// than from the release record's id: it has to be printable at the
  /// moment of printing, and it is far more useful to a person on a
  /// phone call than a random identifier would be.
  static String controlNumber({
    required SchoolDocument document,
    required StudentSummary student,
    required DateTime on,
  }) {
    final stamp = '${on.year.toString().padLeft(4, '0')}'
        '${on.month.toString().padLeft(2, '0')}'
        '${on.day.toString().padLeft(2, '0')}';
    final number = student.studentNumber.isEmpty ? student.id : student.studentNumber;
    return '${document.shortLabel}-$number-$stamp';
  }

  static String fileName({
    required SchoolDocument document,
    required StudentSummary student,
  }) {
    final name = student.fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '${document.shortLabel.toLowerCase()}-$name.pdf';
  }

  /// Renders the document and hands it to the platform's print dialog.
  static Future<void> print({
    required SchoolDocument document,
    required StudentSummary student,
    required SchoolBranding branding,
    required List<Grade> grades,
    required String registrarName,
    String? purpose,
    String? releasedToName,
    int copies = 1,
    DateTime? issuedOn,
  }) async {
    final on = issuedOn ?? DateTime.now();
    await Printing.layoutPdf(
      name: fileName(document: document, student: student),
      onLayout: (_) => build(
        document: document,
        student: student,
        branding: branding,
        grades: grades,
        registrarName: registrarName,
        purpose: purpose,
        releasedToName: releasedToName,
        copies: copies,
        issuedOn: on,
      ),
    );
  }

  static Future<Uint8List> build({
    required SchoolDocument document,
    required StudentSummary student,
    required SchoolBranding branding,
    required List<Grade> grades,
    required String registrarName,
    String? purpose,
    String? releasedToName,
    int copies = 1,
    DateTime? issuedOn,
  }) async {
    final on = issuedOn ?? DateTime.now();
    final doc = pw.Document();

    // Each fetched separately and each guarded: a logo or a signature
    // that fails to load must degrade to its printed name, never abort
    // the document. A registrar standing at a counter needs the sheet.
    final logo = branding.hasLogo ? await pdfImage(branding.logoUrl!) : null;
    final principalSignature =
        branding.hasPrincipalSignature ? await pdfImage(branding.principalSignatureUrl!) : null;

    final terms = _byTerm(grades);
    final control = controlNumber(document: document, student: student, on: on);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginTop: 14 * PdfPageFormat.mm,
          marginBottom: 14 * PdfPageFormat.mm,
          marginLeft: 16 * PdfPageFormat.mm,
          marginRight: 16 * PdfPageFormat.mm,
        ),
        // MultiPage, not Page: a college student with six years of marks
        // runs past one sheet, and a single Page would silently clip the
        // last of them off the bottom -- on the one document where a
        // missing subject is the whole problem.
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _continuationHeader(document, student),
        footer: (context) => _footer(context, control),
        build: (context) => [
          _letterhead(logo, branding),
          pw.SizedBox(height: 10),
          _title(document),
          pw.SizedBox(height: 12),
          _learnerBlock(student, branding, document),
          pw.SizedBox(height: 14),
          _scholasticRecord(terms),
          if (grades.isEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'No marks have been encoded for this student yet.',
              style: pw.TextStyle(
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ],
          if (document == SchoolDocument.form137) ...[
            pw.SizedBox(height: 14),
            _guardianBlock(student),
          ],
          pw.SizedBox(height: 14),
          _issueBlock(
            document: document,
            on: on,
            purpose: purpose,
            releasedToName: releasedToName,
            copies: copies,
          ),
          pw.SizedBox(height: 24),
          _signatures(
            registrarName: registrarName,
            principalName: branding.principalName,
            principalSignature: principalSignature,
          ),
          pw.SizedBox(height: 18),
          _provenance(document),
        ],
      ),
    );

    return doc.save();
  }

  // -----------------------------------------------------------------
  // Layout
  // -----------------------------------------------------------------

  static pw.Widget _letterhead(pw.MemoryImage? logo, SchoolBranding branding) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Image(logo, height: 18 * PdfPageFormat.mm),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  branding.schoolName ?? 'School',
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                ),
                if (branding.addressLine != null)
                  pw.Text(branding.addressLine!, style: const pw.TextStyle(fontSize: 9)),
                if (branding.schoolYear != null)
                  pw.Text(
                    'School Year ${branding.schoolYear}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _title(SchoolDocument document) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(thickness: 1.2, height: 6),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              document.displayLabel.toUpperCase(),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5),
            ),
          ),
          if (document == SchoolDocument.form137)
            pw.Center(
              child: pw.Text(
                'Permanent Academic Record',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
        ],
      );

  /// Repeated at the top of every page after the first, so a sheet that
  /// gets separated from the others can still be identified. A loose
  /// page of somebody's marks with no name on it is the failure mode
  /// this exists for.
  static pw.Widget _continuationHeader(SchoolDocument document, StudentSummary student) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${document.displayLabel} - ${student.fullName}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(student.studentNumber, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      );

  static pw.Widget _learnerBlock(
    StudentSummary student,
    SchoolBranding branding,
    SchoolDocument document,
  ) {
    final rows = <(String, String)>[
      ('Name', _formalName(student)),
      ('Student Number', student.studentNumber),
      if (student.birthDate != null) ('Date of Birth', _longDate.format(student.birthDate!)),
      ('Division', student.educationLevel.displayLabel),
      if (student.programName != null) ('Program / Strand', student.programName!),
      if (student.department != null) ('Department', student.department!),
      ('Grade / Year & Section', student.classLabel),
      ('Status', student.status.displayLabel),
      if (document == SchoolDocument.form137)
        ('Date of Enrolment', _longDate.format(student.enrollmentDate)),
    ];

    return _panel(
      'Learner Information',
      pw.Column(children: [for (final row in rows) _labelledRow(row.$1, row.$2)]),
    );
  }

  static pw.Widget _guardianBlock(StudentSummary student) {
    if (student.guardianContacts.isEmpty) {
      return _panel(
        'Parent / Guardian',
        pw.Text(
          'No parent or guardian is recorded for this student.',
          style: pw.TextStyle(
            fontSize: 9,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700,
          ),
        ),
      );
    }
    return _panel(
      'Parent / Guardian',
      pw.Column(
        children: [
          for (final g in student.guardianContacts)
            _labelledRow(
              g.relationship.isEmpty ? 'Guardian' : g.relationship,
              g.phone.isEmpty ? g.name : '${g.name}, ${g.phone}',
            ),
        ],
      ),
    );
  }

  /// The marks, one block per term.
  ///
  /// Grouped by term rather than listed flat because that is how anyone
  /// reads a record -- a receiving school wants to know what was taken
  /// in Q1, not the order the marks happened to be encoded in.
  static pw.Widget _scholasticRecord(List<_TermGrades> terms) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Scholastic Record',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          for (final term in terms) ...[
            _termTable(term),
            pw.SizedBox(height: 10),
          ],
        ],
      );

  static pw.Widget _termTable(_TermGrades term) {
    final headerStyle = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 9);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: PdfColors.grey200,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(term.term, style: headerStyle),
              pw.Text(
                'General Average: ${term.average.toStringAsFixed(2)}',
                style: headerStyle,
              ),
            ],
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.4),
            4: pw.FlexColumnWidth(2.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _cell('Subject', headerStyle),
                _cell('Section', headerStyle),
                _cell('Score', headerStyle),
                _cell('Rating', headerStyle),
                _cell('Remarks', headerStyle),
              ],
            ),
            for (final g in term.grades)
              pw.TableRow(
                children: [
                  _cell(g.subject, cellStyle),
                  _cell(g.section, cellStyle),
                  _cell('${_trim(g.score)} / ${_trim(g.maxScore)}', cellStyle),
                  _cell(g.percentage.toStringAsFixed(2), cellStyle),
                  // The teacher's own remark stands if there is one. It
                  // says more than a computed verdict, and overwriting it
                  // with "Passed" would discard the only line on the
                  // sheet somebody actually wrote.
                  _cell(g.remarks ?? _verdict(g.percentage), cellStyle),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _issueBlock({
    required SchoolDocument document,
    required DateTime on,
    required String? purpose,
    required String? releasedToName,
    required int copies,
  }) =>
      _panel(
        'Issuance',
        pw.Column(
          children: [
            _labelledRow('Date Issued', _longDate.format(on)),
            if (purpose != null && purpose.trim().isNotEmpty)
              _labelledRow('Purpose', purpose.trim()),
            if (releasedToName != null && releasedToName.trim().isNotEmpty)
              _labelledRow('Released To', releasedToName.trim()),
            if (copies > 1) _labelledRow('Copies', copies.toString()),
          ],
        ),
      );

  static pw.Widget _signatures({
    required String registrarName,
    required String? principalName,
    required pw.MemoryImage? principalSignature,
  }) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _signatory('Registrar', registrarName, null)),
          pw.SizedBox(width: 24),
          pw.Expanded(
            child: _signatory(
              'School Principal',
              principalName,
              principalSignature,
            ),
          ),
        ],
      );

  /// A scan sits above the rule; without one the rule is left blank to
  /// be signed by hand. Both cases occupy the same height so the two
  /// columns stay level -- a school with one signature on file and not
  /// the other would otherwise get a document with one name floating
  /// higher than the other.
  static pw.Widget _signatory(String label, String? name, pw.MemoryImage? signature) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            height: 14 * PdfPageFormat.mm,
            alignment: pw.Alignment.bottomLeft,
            child: signature == null
                ? pw.SizedBox()
                : pw.Image(signature, height: 13 * PdfPageFormat.mm),
          ),
          pw.Container(height: 0.8, color: PdfColors.grey800),
          pw.SizedBox(height: 3),
          // A blank space, not a row of underscores: the rule above is
          // already the line to sign on, and a second dashed line under
          // it reads as a printing fault rather than as "no name set".
          pw.Text(
            name?.trim().isNotEmpty == true ? name!.trim() : ' ',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ],
      );

  static pw.Widget _provenance(SchoolDocument document) => pw.Text(
        'Generated from this school\'s own records. The marks above are the '
        'marks encoded by the subject teachers as at the date of issue; a '
        'quarter not yet encoded will not appear. This is not a government '
        'form: where the ${document == SchoolDocument.form137 ? 'division office' : 'receiving institution'} '
        'requires its own printed template, copy these figures onto it.',
        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
      );

  static pw.Widget _footer(pw.Context context, String control) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(control, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
          ],
        ),
      );

  // -----------------------------------------------------------------
  // Small pieces
  // -----------------------------------------------------------------

  /// A table cell with the padding every cell in this document uses.
  static pw.Widget _cell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Text(text, style: style),
      );

  static pw.Widget _panel(String title, pw.Widget child) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            child,
          ],
        ),
      );

  static pw.Widget _labelledRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 42 * PdfPageFormat.mm,
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9.5)),
            ),
          ],
        ),
      );

  /// "DELA CRUZ, Maria Santos" -- surname first, as school paperwork
  /// files it, and the middle name included because that is what
  /// distinguishes two students with the same first and last name.
  static String _formalName(StudentSummary student) {
    final middle = student.middleName?.trim() ?? '';
    final given = middle.isEmpty ? student.firstName : '${student.firstName} $middle';
    return '${student.lastName.toUpperCase()}, $given';
  }

  static String _verdict(double percentage) =>
      percentage >= _passingRating ? 'Passed' : 'Failed';

  /// Whole marks print whole: "88", not "88.0".
  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  /// Groups marks by term.
  ///
  /// Terms are ordered by the earliest mark encoded in each rather than
  /// alphabetically: "Q1, Q2, Q3, Q4" happens to sort correctly, and
  /// "First Semester, Second Semester" does not. Sorting by when the
  /// marks were actually submitted follows the school year in every
  /// naming scheme.
  static List<_TermGrades> _byTerm(List<Grade> grades) {
    final buckets = <String, List<Grade>>{};
    for (final g in grades) {
      buckets.putIfAbsent(g.term, () => []).add(g);
    }

    final terms = buckets.entries
        .map((e) => _TermGrades(
              term: e.key,
              grades: e.value..sort((a, b) => a.subject.compareTo(b.subject)),
            ))
        .toList()
      ..sort((a, b) => a.earliest.compareTo(b.earliest));
    return terms;
  }
}

/// One term's marks, with the average the school reports.
class _TermGrades {
  final String term;
  final List<Grade> grades;

  _TermGrades({required this.term, required this.grades});

  /// The mean of the subject ratings, not of the raw scores.
  ///
  /// Averaging raw scores would weight a 100-point exam five times
  /// heavier than a 20-point quiz, which is not what a general average
  /// means on a report card.
  double get average => grades.isEmpty
      ? 0
      : grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length;

  DateTime get earliest =>
      grades.map((g) => g.submittedAt).reduce((a, b) => a.isBefore(b) ? a : b);
}
