import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/clearance.dart';

final _longDate = DateFormat('d MMMM y');
final _peso = NumberFormat.currency(locale: 'en_PH', symbol: 'PHP ');

/// The slip a student hands the proctor.
///
/// Small on purpose -- half a page, two to a sheet -- because a school
/// prints one per student per examination and a full page each is a ream
/// per section. Everything a proctor checks is in the top third: the
/// name, the section, the examination, and whether it says PERMITTED.
///
/// ASCII punctuation only. The built-in Helvetica silently drops an em
/// dash and the peso sign, which is why the currency format above spells
/// out PHP -- a permit printed with a blank where the amount should be is
/// worse than one with an ugly amount.
class ExamPermitPdf {
  ExamPermitPdf._();

  static String fileName(String studentName, String examination) {
    String slug(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return 'permit-${slug(studentName)}-${slug(examination)}.pdf';
  }

  static Future<void> print({
    required String studentName,
    required String studentNumber,
    required String classLabel,
    required String examination,
    required Clearance clearance,
    required SchoolBranding branding,
    required String issuedByName,
    DateTime? on,
  }) async {
    final bytes = await build(
      studentName: studentName,
      studentNumber: studentNumber,
      classLabel: classLabel,
      examination: examination,
      clearance: clearance,
      branding: branding,
      issuedByName: issuedByName,
      on: on,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName(studentName, examination),
    );
  }

  static Future<Uint8List> build({
    required String studentName,
    required String studentNumber,
    required String classLabel,
    required String examination,
    required Clearance clearance,
    required SchoolBranding branding,
    required String issuedByName,
    DateTime? on,
  }) async {
    final issued = on ?? DateTime.now();
    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              (branding.schoolName ?? "").toUpperCase(),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text('EXAMINATION PERMIT', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(height: 14),
            _row('Student', studentName),
            _row('Student No.', studentNumber),
            _row('Class', classLabel),
            _row('Examination', examination),
            pw.SizedBox(height: 12),
            // The one thing a proctor reads. Boxed and in capitals
            // because this slip is checked at arm's length in a queue,
            // and a permit whose verdict has to be hunted for is one that
            // gets waved through.
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1.2),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    clearance.isCleared ? 'PERMITTED TO TAKE THE EXAMINATION'
                        : 'NOT PERMITTED',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(_reason(clearance), style: const pw.TextStyle(fontSize: 8.5)),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Issued ${_longDate.format(issued)} by $issuedByName',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Container(
                  width: 150,
                  child: pw.Column(
                    children: [
                      pw.Divider(height: 1),
                      pw.SizedBox(height: 2),
                      pw.Text('Cashier', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              // Said on the slip itself, because a permit printed on
              // Monday and presented on Friday is the failure this
              // sentence exists to head off.
              'Valid for the examination named above. Account status as at '
              '${_longDate.format(issued)}.',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 80,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      );

  static String _reason(Clearance clearance) => switch (clearance.outcome) {
        ClearanceOutcome.cleared => 'Account is current. Nothing is overdue.',
        ClearanceOutcome.clearedByNote =>
          'Covered by an approved promissory note'
              '${clearance.note?.settleBy == null ? '' : ', to settle by '
                  '${_longDate.format(clearance.note!.settleBy!)}'}. '
              'Overdue ${_peso.format(clearance.overdue)}.',
        ClearanceOutcome.blocked =>
          'Overdue ${_peso.format(clearance.overdue)}. '
              '${_peso.format(clearance.shortfall)} remains uncovered. '
              'Settle at the cashier, or file a promissory note.',
      };
}
