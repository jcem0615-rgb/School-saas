import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Reads and writes real `.xlsx` workbooks -- the format Microsoft Excel,
/// WPS Office and Google Sheets all open natively.
///
/// CSV is still here (see [Csv]) and still useful, but it is the wrong
/// default for a school's roster. Excel and WPS both treat a CSV as a
/// suggestion: `2024-00001` becomes a date, `09171234567` loses its
/// leading zero, and an enye survives or does not depending on whether
/// the machine's regional setting happens to be UTF-8. A registrar
/// exporting a file, mailing it to the division office and having the
/// student numbers arrive mangled is not a hypothetical -- it is the
/// normal outcome.
///
/// Every cell is written as text for exactly that reason. A student
/// number is an identifier that happens to be made of digits, not a
/// quantity, and the moment Excel is allowed to guess it stops being the
/// same string it started as.
class Workbook {
  Workbook._();

  /// Builds a one-sheet workbook: [headers] as the first row, then [rows].
  static Uint8List encode(
    List<String> headers,
    List<List<String>> rows, {
    String sheetName = 'Sheet1',
  }) {
    final book = Excel.createExcel();

    // createExcel() seeds a sheet of its own; renaming it is safer than
    // adding a second one and deleting the first, which leaves the
    // workbook briefly sheetless and is refused.
    final seeded = book.getDefaultSheet();
    if (seeded != null && seeded != sheetName) {
      book.rename(seeded, sheetName);
    }

    final sheet = book[sheetName];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final row in rows) {
      sheet.appendRow([for (final cell in row) TextCellValue(cell)]);
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw StateError('The workbook could not be written.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Reads the first sheet that has anything in it, as rows of strings.
  ///
  /// The first sheet "that has anything in it" rather than simply the
  /// first: a workbook someone has been working in often carries an empty
  /// Sheet2 and Sheet3 in front of, or behind, the data, and refusing to
  /// import because the alphabetically-first tab is blank would be a
  /// bewildering thing to tell a registrar.
  static List<List<String>> decode(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    for (final sheet in book.tables.values) {
      final table = _readSheet(sheet);
      if (table.isNotEmpty) return table;
    }
    return const [];
  }

  static List<List<String>> _readSheet(Sheet sheet) {
    final table = <List<String>>[];
    for (final row in sheet.rows) {
      final cells = [for (final cell in row) _asText(cell?.value)];
      // Excel pads rows out to the width of the widest one, so almost
      // every row arrives with trailing blanks that are not really there.
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      if (cells.isEmpty) continue; // a spacer row, not a record
      table.add(cells);
    }
    return table;
  }

  static String _asText(CellValue? value) {
    switch (value) {
      case null:
        return '';
      case TextCellValue():
        return value.value.toString().trim();
      case IntCellValue():
        return value.value.toString();
      case DoubleCellValue():
        // 7.0 is a grade level someone typed as a number, not a quantity
        // measured to one decimal place.
        final d = value.value;
        return d == d.roundToDouble() && d.abs() < 1e15
            ? d.toInt().toString()
            : d.toString();
      case DateCellValue():
        return _isoDate(value.year, value.month, value.day);
      case DateTimeCellValue():
        return _isoDate(value.year, value.month, value.day);
      case BoolCellValue():
        return value.value ? 'TRUE' : 'FALSE';
      default:
        return value.toString().trim();
    }
  }

  /// Dates come back as `YYYY-MM-DD` whether the cell was text or a real
  /// Excel date. Someone who typed a birthday into a date-formatted
  /// column and someone who typed it into a text one have entered the
  /// same birthday, and the importer should not be able to tell.
  static String _isoDate(int year, int month, int day) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
