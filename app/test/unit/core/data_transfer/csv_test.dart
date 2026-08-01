import 'package:flutter_test/flutter_test.dart';
import 'package:school_saas/core/data_transfer/csv.dart';

/// School data is full of the exact things naive CSV handling breaks on:
/// names with commas ("Dela Cruz, Jr."), remarks with quotes, addresses
/// with newlines. Getting any of them wrong silently shifts every column
/// after it, which is far worse than failing outright -- an import would
/// appear to succeed and write nonsense.
void main() {
  group('encode', () {
    test('leaves ordinary fields alone', () {
      expect(
        Csv.encode(['a', 'b'], [
          ['1', '2']
        ]),
        'a,b\n1,2\n',
      );
    });

    test('quotes a field containing a comma', () {
      final out = Csv.encode(['Name'], [
        ['Dela Cruz, Jr.']
      ]);
      expect(out, 'Name\n"Dela Cruz, Jr."\n');
    });

    test('doubles embedded quotes', () {
      final out = Csv.encode(['Remarks'], [
        ['Said "hello"']
      ]);
      expect(out, 'Remarks\n"Said ""hello"""\n');
    });

    test('quotes a field containing a newline', () {
      final out = Csv.encode(['Address'], [
        ['Line 1\nLine 2']
      ]);
      expect(out, 'Address\n"Line 1\nLine 2"\n');
    });
  });

  group('decode', () {
    test('reads a plain table', () {
      expect(Csv.decode('a,b\n1,2\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('a quoted comma stays one field', () {
      expect(Csv.decode('Name\n"Dela Cruz, Jr."\n'), [
        ['Name'],
        ['Dela Cruz, Jr.'],
      ]);
    });

    test('doubled quotes come back as one quote', () {
      expect(Csv.decode('Remarks\n"Said ""hello"""\n'), [
        ['Remarks'],
        ['Said "hello"'],
      ]);
    });

    test('a quoted newline does not split the row', () {
      expect(Csv.decode('Address\n"Line 1\nLine 2"\n'), [
        ['Address'],
        ['Line 1\nLine 2'],
      ]);
    });

    test('handles CRLF, which is what a Windows spreadsheet exports', () {
      expect(Csv.decode('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('a missing trailing newline still yields the last row', () {
      expect(Csv.decode('a,b\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('empty input is no rows, not one blank row', () {
      expect(Csv.decode(''), isEmpty);
      expect(Csv.decode('\n'), isEmpty);
    });

    test('empty fields are preserved, so columns do not shift', () {
      expect(Csv.decode('a,b,c\n1,,3\n'), [
        ['a', 'b', 'c'],
        ['1', '', '3'],
      ]);
    });
  });

  group('round trip', () {
    test('survives every character class that needs escaping', () {
      const headers = ['Name', 'Remarks', 'Address'];
      final rows = [
        ['Dela Cruz, Jr.', 'Said "hello"', 'Line 1\nLine 2'],
        ['Plain', '', 'Nothing special'],
      ];

      final decoded = Csv.decode(Csv.encode(headers, rows));
      expect(decoded.first, headers);
      expect(decoded.sublist(1), rows);
    });
  });
}
