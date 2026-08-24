import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';

import 'package:logicclass/core/data_transfer/workbook.dart';

/// The whole point of writing .xlsx instead of .csv is that the bytes
/// survive a round trip through Excel and WPS unchanged. These tests hold
/// the cases that do not survive CSV.
void main() {
  group('Workbook', () {
    test('round-trips headers and rows', () {
      final bytes = Workbook.encode(
        const ['Last Name', 'First Name'],
        const [
          ['Dela Cruz', 'Maria'],
          ['Reyes', 'Juan'],
        ],
      );

      expect(Workbook.decode(bytes), [
        ['Last Name', 'First Name'],
        ['Dela Cruz', 'Maria'],
        ['Reyes', 'Juan'],
      ]);
    });

    test('a student number keeps its leading zeros and does not become a date', () {
      // The CSV failure this format exists to avoid: Excel reads
      // 2024-00001 as a date and 09171234567 as a number.
      final bytes = Workbook.encode(
        const ['Student Number', 'Guardian Phone'],
        const [
          ['2024-00001', '09171234567'],
        ],
      );

      expect(Workbook.decode(bytes)[1], ['2024-00001', '09171234567']);
    });

    test('an enye survives', () {
      final bytes = Workbook.encode(const ['Last Name'], const [
        ['Muñoz'],
      ]);
      expect(Workbook.decode(bytes)[1], ['Muñoz']);
    });

    test('a comma in a name needs no escaping and gains none', () {
      final bytes = Workbook.encode(const ['Name'], const [
        ['Reyes, Juan Jr.'],
      ]);
      expect(Workbook.decode(bytes)[1], ['Reyes, Juan Jr.']);
    });

    test('no rows is a header-only template, not an empty file', () {
      final bytes = Workbook.encode(const ['Last Name', 'First Name'], const []);
      expect(Workbook.decode(bytes), [
        ['Last Name', 'First Name'],
      ]);
    });

    test('a number typed into a cell reads back without a decimal tail', () {
      // What a registrar gets when they type 7 into the Grade Level
      // column: a numeric cell, which must not import as "7.0".
      final book = Excel.createExcel();
      final sheet = book[book.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Grade Level')]);
      sheet.appendRow([IntCellValue(7)]);
      sheet.appendRow([DoubleCellValue(8.0)]);
      sheet.appendRow([DoubleCellValue(8.5)]);

      final table = Workbook.decode(Uint8List.fromList(book.encode()!));
      expect(table.sublist(1), [
        ['7'],
        ['8'],
        ['8.5'],
      ]);
    });

    test('a date cell reads back as an ISO date', () {
      final book = Excel.createExcel();
      final sheet = book[book.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Birthday')]);
      sheet.appendRow([DateCellValue(year: 2012, month: 3, day: 7)]);

      expect(Workbook.decode(Uint8List.fromList(book.encode()!))[1], ['2012-03-07']);
    });

    test('blank spacer rows are dropped, not imported as empty students', () {
      final book = Excel.createExcel();
      final sheet = book[book.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Last Name')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Reyes')]);

      expect(Workbook.decode(Uint8List.fromList(book.encode()!)), [
        ['Last Name'],
        ['Reyes'],
      ]);
    });
  });
}
