import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/storage/pdf_image.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/schedule_block.dart';

final _longDate = DateFormat('d MMMM y');

/// The timetable as a grid, which is where a grid belongs.
///
/// On screen it is a list, because a five-by-ten grid does not fit a
/// phone. On paper it is the thing that gets taped to the classroom
/// door, and there it has to be a grid: a parent standing in a corridor
/// reads down a column to find out where their child is at ten o'clock.
///
/// Rows are the distinct start times actually used rather than a fixed
/// hourly ruler. A school running 7:30, 8:20, 9:10 would get a grid full
/// of empty half-rows from an hourly one, and one running a 40-minute
/// homeroom would have it fall between the lines entirely.
///
/// ASCII punctuation only -- the built-in Helvetica silently drops an em
/// dash, and a timetable is exactly the document nobody proofreads
/// before pinning it up.
class TimetablePdf {
  TimetablePdf._();

  static String fileName(String title) {
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return 'timetable-$slug.pdf';
  }

  static Future<void> print({
    required String title,
    required String subtitle,
    required List<ScheduleBlock> blocks,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    final bytes = await build(
      title: title,
      subtitle: subtitle,
      blocks: blocks,
      branding: branding,
      preparedByName: preparedByName,
      on: on,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName(title));
  }

  static Future<Uint8List> build({
    required String title,
    required String subtitle,
    required List<ScheduleBlock> blocks,
    required SchoolBranding branding,
    required String preparedByName,
    DateTime? on,
  }) async {
    final printedOn = on ?? DateTime.now();
    final logo = await pdfImage(branding.logoUrl ?? '');

    // Only the days that have classes, in week order. A school with no
    // Saturday classes gets a five-column grid, not a seven-column one
    // with two columns of white space.
    final days = blocks.map((b) => b.dayOfWeek).toSet().toList()..sort();
    // Distinct slots, by start time. Two subjects starting at 7:30 on
    // different days share a row, which is what makes it a grid.
    final starts = blocks.map((b) => b.startMinute).toSet().toList()..sort();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: days.length > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _letterhead(logo, branding),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1.2, height: 6),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
            pw.Center(
              child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ),
            pw.SizedBox(height: 12),
            if (blocks.isEmpty)
              pw.Text('No classes are timetabled.', style: const pw.TextStyle(fontSize: 10))
            else
              // A section's own sheet already says the section in the
              // title; repeating it in all thirty cells is thirty
              // repetitions of something nobody is reading the grid to
              // find out. The same goes for a single teacher's sheet.
              _grid(
                blocks,
                days,
                starts,
                showSection: blocks.map((b) => b.section).toSet().length > 1,
                showTeacher: blocks.map((b) => b.teacherId).toSet().length > 1,
              ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Prepared by $preparedByName on ${_longDate.format(printedOn)}',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                ),
                pw.Text(
                  'Timetables change. Check the date above before relying on this sheet.',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

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
              ],
            ),
          ),
        ],
      );

  static pw.Widget _grid(
    List<ScheduleBlock> blocks,
    List<int> days,
    List<int> starts, {
    required bool showSection,
    required bool showTeacher,
  }) {
    // One cell per (slot, day). A block occupying a slot on a day lands
    // in exactly one cell; two blocks in the same cell means the same
    // section is double-booked, which the callable refuses -- but a
    // timetable printed from data written before that check existed
    // should still print both rather than silently drop one.
    final cells = <String, List<ScheduleBlock>>{};
    for (final block in blocks) {
      (cells['${block.startMinute}|${block.dayOfWeek}'] ??= []).add(block);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(64),
        for (var i = 0; i < days.length; i++) i + 1: const pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _headerCell('Time'),
            for (final day in days) _headerCell(weekdayLabel(day)),
          ],
        ),
        for (final start in starts)
          pw.TableRow(
            children: [
              _timeCell(start, blocks),
              for (final day in days)
                _classCell(
                  cells['$start|$day'] ?? const [],
                  showSection: showSection,
                  showTeacher: showTeacher,
                ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _headerCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      );

  /// The row label shows the slot's own end time, taken from a block
  /// that actually starts then -- so a 40-minute homeroom reads
  /// 7:30-8:10 rather than being squared up to the hour.
  static pw.Widget _timeCell(int start, List<ScheduleBlock> blocks) {
    final ends = blocks.where((b) => b.startMinute == start).map((b) => b.endMinute).toSet();
    final label = ends.length == 1
        ? '${formatMinuteOfDay(start)}\n${formatMinuteOfDay(ends.first)}'
        : formatMinuteOfDay(start);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
    );
  }

  static pw.Widget _classCell(
    List<ScheduleBlock> blocks, {
    required bool showSection,
    required bool showTeacher,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(4),
        constraints: const pw.BoxConstraints(minHeight: 28),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final block in blocks) ...[
              pw.Text(
                block.subject,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                [
                  if (showSection) block.section,
                  if (showTeacher) block.teacherName,
                  if (block.room != null) block.room!,
                ].join(' / '),
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
              ),
            ],
          ],
        ),
      );
}
