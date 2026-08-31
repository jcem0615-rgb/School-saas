import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/grading_scheme.dart';
import '../../domain/entities/quarterly_grade.dart';

final _longDate = DateFormat('d MMMM y');

/// The report card, in the shape a Philippine parent expects.
///
/// Subjects down the left, quarters across, the final grade and its
/// descriptor at the right. This is the document the whole grading
/// feature exists to produce: a school that cannot issue one keeps a
/// parallel spreadsheet, and once the spreadsheet exists it becomes the
/// record and this becomes decoration.
///
/// ASCII punctuation only -- the built-in Helvetica drops an em dash
/// silently, and a report card is not a document anybody proofreads twice.
class ReportCardPdf {
  ReportCardPdf._();

  static String fileName(String studentName) {
    final slug = studentName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return 'report-card-$slug.pdf';
  }

  static Future<void> print({
    required String studentName,
    required String studentNumber,
    required String classLabel,
    required String schoolYear,
    required List<String> terms,
    required Map<String, List<QuarterlyGrade>> bySubject,
    required GradingScheme scheme,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    final bytes = await build(
      studentName: studentName,
      studentNumber: studentNumber,
      classLabel: classLabel,
      schoolYear: schoolYear,
      terms: terms,
      bySubject: bySubject,
      scheme: scheme,
      branding: branding,
      preparedByName: preparedByName,
      on: on,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName(studentName));
  }

  static Future<Uint8List> build({
    required String studentName,
    required String studentNumber,
    required String classLabel,
    required String schoolYear,
    required List<String> terms,
    required Map<String, List<QuarterlyGrade>> bySubject,
    required GradingScheme scheme,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    // The refusal that makes the confirmation mean something.
    //
    // The weights this is computed from are seeded with the DepEd
    // groupings, which is a starting point transcribed from a public
    // order and not this software's assertion about what a school's
    // grades should be. A report card printed off unconfirmed defaults
    // would make them exactly that -- a document with the school's name
    // on it, asserting grades nobody at the school has agreed the basis
    // of. So it does not print until somebody there has said the weights
    // are right.
    if (!scheme.confirmedBySchool) {
      throw StateError(
        'The grading scheme has not been confirmed. Somebody at the school '
        'has to check the weights on the Grading Scheme screen before '
        'report cards can be printed.',
      );
    }

    final issued = on ?? DateTime.now();
    final document = pw.Document();

    final subjects = bySubject.keys.toList()..sort();

    // The average across every graded subject and quarter, which is what
    // a parent reads first.
    final everything = [for (final list in bySubject.values) ...list];
    final average = generalAverage(everything);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              (branding.schoolName ?? '').toUpperCase(),
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('REPORT ON LEARNING PROGRESS AND ACHIEVEMENT',
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              pw.Expanded(child: _field('Name', studentName)),
              pw.Expanded(child: _field('Student No.', studentNumber)),
            ]),
            pw.Row(children: [
              pw.Expanded(child: _field('Class', classLabel)),
              pw.Expanded(child: _field('School Year', schoolYear)),
            ]),
            pw.SizedBox(height: 12),
            _gradeTable(subjects: subjects, terms: terms, bySubject: bySubject),
            pw.SizedBox(height: 10),
            if (average != null)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
                child: pw.Text(
                  'General Average  $average   ${gradeDescriptor(average)}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
            pw.SizedBox(height: 12),
            _legend(),
            pw.Spacer(),
            // Says how the numbers were arrived at, on the document
            // itself. A grade a parent cannot trace is one they have to
            // take on trust, and the weights are not the same for every
            // subject -- which is exactly the thing people assume.
            pw.Text(
              'Grades are computed from Written Work, Performance Tasks and '
              'Quarterly Assessment, weighted per subject under the grading '
              'scheme confirmed by the school'
              '${scheme.confirmedByName == null ? '' : ' (${scheme.confirmedByName})'}'
              '. A subject with no work recorded in a quarter is left blank '
              'rather than scored zero.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _signature('Class Adviser', preparedByName),
                _signature('Principal', branding.principalName ?? ''),
                _signature('Parent / Guardian', ''),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text('Issued ${_longDate.format(issued)}',
                style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _gradeTable({
    required List<String> subjects,
    required List<String> terms,
    required Map<String, List<QuarterlyGrade>> bySubject,
  }) {
    pw.Widget cell(String text, {bool header = false, pw.TextAlign? align}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        for (var i = 0; i < terms.length; i++) i + 1: const pw.FlexColumnWidth(1),
        terms.length + 1: const pw.FlexColumnWidth(1),
        terms.length + 2: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            cell('Learning Area', header: true),
            for (final term in terms)
              cell(term, header: true, align: pw.TextAlign.center),
            cell('Final', header: true, align: pw.TextAlign.center),
            cell('Remarks', header: true),
          ],
        ),
        for (final subject in subjects)
          _subjectRow(subject, terms, bySubject[subject] ?? const [], cell),
      ],
    );
  }

  static pw.TableRow _subjectRow(
    String subject,
    List<String> terms,
    List<QuarterlyGrade> grades,
    pw.Widget Function(String, {bool header, pw.TextAlign? align}) cell,
  ) {
    final byTerm = {for (final g in grades) g.term: g};
    final graded = grades.where((g) => g.hasWork).toList();
    final finalGrade = graded.isEmpty
        ? null
        : (graded.fold<int>(0, (sum, g) => sum + g.finalGrade) / graded.length).round();

    return pw.TableRow(children: [
      cell(subject),
      for (final term in terms)
        cell(
          // Blank, not zero. A subject the teacher has not entered
          // anything for did not earn a nought.
          byTerm[term]?.hasWork == true ? '${byTerm[term]!.finalGrade}' : '',
          align: pw.TextAlign.center,
        ),
      cell(finalGrade == null ? '' : '$finalGrade', align: pw.TextAlign.center),
      cell(finalGrade == null ? '' : (isPassing(finalGrade) ? 'Passed' : 'Failed')),
    ]);
  }

  static pw.Widget _legend() => pw.Text(
        'Descriptors:  90-100 Outstanding   85-89 Very Satisfactory   '
        '80-84 Satisfactory   75-79 Fairly Satisfactory   '
        'Below 75 Did Not Meet Expectations',
        style: const pw.TextStyle(fontSize: 7.5),
      );

  static pw.Widget _field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Text('$label: ', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _signature(String role, String name) => pw.Container(
        width: 150,
        child: pw.Column(children: [
          pw.SizedBox(height: 14),
          pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(height: 1),
          pw.SizedBox(height: 2),
          pw.Text(role, style: const pw.TextStyle(fontSize: 7.5)),
        ]),
      );
}
