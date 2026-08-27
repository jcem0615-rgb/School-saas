import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/storage/pdf_image.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/report_table.dart';

final _longDate = DateFormat('d MMMM y');
final _timestamp = DateFormat('d MMM y, h:mm a');

/// Any [ReportTable], on the school's letterhead.
///
/// One builder for every report, which is the payoff of fixing the table
/// shape: a fifth report prints correctly the day it is written, with
/// nothing added here.
///
/// Landscape, unlike the transcript. A report is wide -- ten columns for
/// attendance, ten for grades -- and portrait would either shrink the
/// figures past reading or drop the columns on the right, which on a
/// printed sheet is silent.
///
/// Punctuation is ASCII throughout, for the reason set out in
/// AcademicRecordPdf: the built-in Helvetica has no glyph for an em dash
/// or a peso sign and drops them without complaint, so a peso figure
/// would print as a bare number and nobody would find out until the
/// sheet was in somebody's hand.
class ReportPdf {
  ReportPdf._();

  static String fileName(ReportTable table) {
    final slug = table.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return '$slug-$stamp.pdf';
  }

  static Future<void> print({
    required ReportTable table,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    final bytes = await build(
      table: table,
      branding: branding,
      preparedByName: preparedByName,
      on: on,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName(table),
    );
  }

  static Future<Uint8List> build({
    required ReportTable table,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    final printedOn = on ?? DateTime.now();
    // pdfImage rather than networkImage: an uploaded logo is a data: URI
    // in demo mode and on any deployment whose uploads are inlined, and
    // networkImage cannot fetch one -- it fails silently, which is how a
    // letterhead loses its crest without anyone being told.
    final logo = await pdfImage(branding.logoUrl ?? '');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(
          14 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          14 * PdfPageFormat.mm,
          14 * PdfPageFormat.mm,
        ),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _continuationHeader(table, context.pageNumber),
        footer: (context) => _footer(context, printedOn, preparedByName),
        build: (context) => [
          _letterhead(logo, branding),
          pw.SizedBox(height: 8),
          _title(table),
          pw.SizedBox(height: 12),
          if (table.headline.isNotEmpty) ...[
            _headline(table),
            pw.SizedBox(height: 14),
          ],
          if (table.isEmpty)
            pw.Text(
              'No records fall in this period.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else
            _table(table),
          if (table.note != null) ...[
            pw.SizedBox(height: 12),
            _note(table.note!),
          ],
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
            pw.Image(logo, height: 16 * PdfPageFormat.mm),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  branding.schoolName ?? 'School',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                if (branding.addressLine != null)
                  pw.Text(branding.addressLine!, style: const pw.TextStyle(fontSize: 8.5)),
                if (branding.schoolYear != null)
                  pw.Text(
                    'School Year ${branding.schoolYear}',
                    style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                  ),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _title(ReportTable table) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(thickness: 1.2, height: 6),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              table.title.toUpperCase(),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1.4),
            ),
          ),
          pw.Center(
            child: pw.Text(
              table.subtitle,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ],
      );

  static pw.Widget _headline(ReportTable table) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final stat in table.headline)
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(right: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      stat.label.toUpperCase(),
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      stat.value,
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                    if (stat.caption != null)
                      pw.Text(
                        stat.caption!,
                        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );

  static pw.Widget _table(ReportTable table) {
    // Which data rows are totals. TableHelper counts the header as row
    // 0, so a data row's own index is one less than the rowNum it hands
    // back.
    final totalRows = <int>{
      for (var i = 0; i < table.rows.length; i++)
        if (table.rows[i].isTotal) i,
    };

    return pw.TableHelper.fromTextArray(
      headers: table.headers,
      data: table.cellRows,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellHeight: 16,
      // Text left, figures right. A column of numbers that does not line
      // up is one nobody can read down, which is most of what a reader
      // does with a report like this.
      cellAlignments: {
        for (var i = 0; i < table.columns.length; i++)
          i: table.columns[i].numeric ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      },
      headerAlignments: {
        for (var i = 0; i < table.columns.length; i++)
          i: table.columns[i].numeric ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      },
      // The totals row is shaded and ruled off. Without it the printed
      // sheet ends with "All divisions" reading as one more division,
      // which is the row somebody quotes.
      cellDecoration: (column, data, row) => totalRows.contains(row - 1)
          ? const pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border(top: pw.BorderSide(width: 1)),
            )
          : const pw.BoxDecoration(),
    );
  }

  static pw.Widget _note(String note) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ABOUT THESE FIGURES',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 3),
            pw.Text(note, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );

  /// A loose sheet of figures with no title on it is the failure mode
  /// this exists for -- the same reason the transcript repeats the
  /// student's name on every page.
  static pw.Widget _continuationHeader(ReportTable table, int page) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${table.title} - ${table.subtitle}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Page $page', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );

  /// Who ran it and when, on every page.
  ///
  /// A report without those two facts is one nobody can act on six weeks
  /// later: figures that moved since are indistinguishable from figures
  /// that were wrong, and there is nobody to ask.
  static pw.Widget _footer(pw.Context context, DateTime on, String preparedByName) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Prepared by $preparedByName on ${_longDate.format(on)} '
              '(${_timestamp.format(on)})',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
      );
}
