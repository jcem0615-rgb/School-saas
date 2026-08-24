import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/data_transfer/csv.dart' show ImportIssue;
import 'package:logicclass/core/data_transfer/import_columns.dart';

void main() {
  const wanted = ['Last Name', 'First Name', 'Division'];

  group('ImportColumns.resolve', () {
    test('finds columns in the order the file happens to have them', () {
      final columns = ImportColumns.resolve(
        ['Division', 'First Name', 'Last Name'],
        wanted,
      );
      expect(columns, [2, 1, 0]);
    });

    test('ignores columns the importer has no use for', () {
      // Exactly the shape of a file exported by this app: it carries
      // Student Number, Status and Balance, which the importer skips.
      final columns = ImportColumns.resolve(
        ['Student Number', 'Last Name', 'First Name', 'Division', 'Balance'],
        wanted,
      );
      expect(columns, [1, 2, 3]);
    });

    test('matching is case and whitespace insensitive', () {
      final columns = ImportColumns.resolve(
        ['  LAST NAME ', 'first name', 'Division'],
        wanted,
      );
      expect(columns, [0, 1, 2]);
    });

    test('names every missing column at once, not just the first', () {
      final result = ImportColumns.resolve(['First Name'], wanted);
      expect(result, isA<ImportIssue>());
      final issue = result as ImportIssue;
      expect(issue.row, 1);
      expect(issue.message, contains('Last Name'));
      expect(issue.message, contains('Division'));
    });

    test('one missing column reads as one, not "columns"', () {
      final issue = ImportColumns.resolve(['Last Name', 'First Name'], wanted) as ImportIssue;
      expect(issue.message, contains('missing a column'));
    });
  });

  group('ImportColumns.reorder', () {
    test('puts a row into the wanted order', () {
      expect(
        ImportColumns.reorder(['College', 'Maria', 'Dela Cruz'], [2, 1, 0]),
        ['Dela Cruz', 'Maria', 'College'],
      );
    });

    test('a short row blanks the cells it does not have', () {
      // Neither CSV nor Excel writes trailing empty cells, so the last
      // columns of a row simply are not there.
      expect(ImportColumns.reorder(['Reyes'], [0, 1, 2]), ['Reyes', '', '']);
    });
  });
}
