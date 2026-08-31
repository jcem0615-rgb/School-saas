import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/payslip.dart';

final _longDate = DateFormat('d MMMM y');
final _amount = NumberFormat('#,##0.00');

/// The payslip, in the shape somebody actually reads.
///
/// Earnings on the left, deductions on the right, net pay boxed at the
/// bottom, and the basis of every line printed underneath it -- "3 days
/// at 1,363.64", "SSS Circular 2025-006". A deduction an employee cannot
/// trace is one they have to take on trust, and pay is the last place
/// anybody should be asked to.
///
/// ASCII punctuation only. The built-in Helvetica has no glyph for a
/// peso sign or an em dash and drops them silently, which on a payslip
/// would mean an amount printed with nothing in front of it.
class PayslipPdf {
  PayslipPdf._();

  static String fileName(Payslip payslip) {
    final slug = payslip.employeeName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return 'payslip-$slug-${payslip.periodFrom}.pdf';
  }

  static Future<void> print({
    required Payslip payslip,
    required SchoolBranding branding,
    DateTime? on,
  }) async {
    final bytes = await build(payslip: payslip, branding: branding, on: on);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName(payslip),
    );
  }

  static Future<Uint8List> build({
    required Payslip payslip,
    required SchoolBranding branding,
    DateTime? on,
  }) async {
    final issued = on ?? DateTime.now();
    final document = pw.Document();

    document.addPage(
      pw.Page(
        // A5 landscape: two of these fit a sheet of A4, which is how a
        // school with forty staff actually prints them.
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text((branding.schoolName ?? '').toUpperCase(),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text('PAYSLIP', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Expanded(child: _field('Employee', payslip.employeeName)),
              pw.Expanded(
                child: _field('Period', '${payslip.periodFrom} to ${payslip.periodTo}'),
              ),
            ]),
            pw.SizedBox(height: 10),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _column('Earnings', payslip.earnings)),
                pw.SizedBox(width: 14),
                pw.Expanded(child: _column('Deductions', payslip.deductions)),
              ],
            ),

            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('NET PAY',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_amount.format(payslip.netPay),
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),

            pw.SizedBox(height: 8),
            // The attendance behind the figures, so a deduction for
            // absence is checkable against something rather than
            // asserted.
            pw.Text(
              '${payslip.daysWorked} days worked, ${payslip.daysAbsent} absent, '
              '${payslip.daysLate} late.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
            // Said on the document, not only on the screen. An hourly
            // payslip computed from days that were never closed is a
            // figure the school cannot stand behind, and the person
            // holding it should know that before they bank on it.
            if (payslip.hoursAreIncomplete)
              pw.Text(
                '${payslip.daysMissingTimeOut} day(s) were scanned in and not '
                'out. The hours for those days are not known and are not paid '
                'here -- raise it with the office.',
                style: const pw.TextStyle(fontSize: 7.5),
              ),

            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _signature('Received by', payslip.employeeName),
                _signature('Prepared by', branding.directorName ?? ''),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Issued ${_longDate.format(issued)}',
                style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _column(String heading, List<PayslipLine> lines) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(heading,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Divider(height: 4),
          if (lines.isEmpty)
            pw.Text('None', style: const pw.TextStyle(fontSize: 8))
          else
            for (final line in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(line.label,
                              style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Text(_amount.format(line.amount),
                            style: const pw.TextStyle(fontSize: 8.5)),
                      ],
                    ),
                    if (line.basis != null && line.basis!.isNotEmpty)
                      pw.Text(line.basis!, style: const pw.TextStyle(fontSize: 6.5)),
                  ],
                ),
              ),
          pw.Divider(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                _amount.format(lines.fold<double>(0, (sum, l) => sum + l.amount)),
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      );

  static pw.Widget _field(String label, String value) => pw.Row(children: [
        pw.Text('$label: ', style: const pw.TextStyle(fontSize: 8)),
        pw.Expanded(
          child: pw.Text(value,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ),
      ]);

  static pw.Widget _signature(String role, String name) => pw.SizedBox(
        width: 150,
        child: pw.Column(children: [
          pw.SizedBox(height: 12),
          pw.Text(name, style: const pw.TextStyle(fontSize: 7.5)),
          pw.Divider(height: 1),
          pw.Text(role, style: const pw.TextStyle(fontSize: 7)),
        ]),
      );
}
