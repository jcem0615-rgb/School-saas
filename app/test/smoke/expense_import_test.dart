import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/data_transfer/csv.dart' show ImportIssue;
import 'package:logicclass/features/director_portal/domain/entities/expense.dart';
import 'package:logicclass/features/director_portal/presentation/import/expense_import.dart';

/// The expense ledger is what the school's budget reporting is built on,
/// so these tests are mostly about what the importer refuses.
void main() {
  const categories = ['Utilities', 'Supplies', 'Maintenance'];

  List<String> row({
    String date = '2026-03-07',
    String category = 'Utilities',
    String description = 'Meralco bill',
    String amount = '4250.00',
  }) =>
      [date, category, description, amount];

  Object? parse(
    List<String> r, {
    List<Expense> existing = const [],
    Set<String>? seen,
  }) =>
      ExpenseImport.parseRow(
        row: r,
        rowNumber: 2,
        categories: categories,
        existing: existing,
        seen: seen ?? <String>{},
      );

  group('a good row', () {
    test('becomes an expense', () {
      final parsed = parse(row());
      expect(parsed, isA<ExpenseImportRow>());
      final e = parsed as ExpenseImportRow;
      expect(e.category, 'Utilities');
      expect(e.description, 'Meralco bill');
      expect(e.amount, 4250.00);
      expect(e.date, DateTime(2026, 3, 7));
    });

    test('takes the category from the catalogue, not as typed', () {
      // So that "utilities" and "Utilities" land in the same line of the
      // expense report rather than two.
      final e = parse(row(category: 'utilities')) as ExpenseImportRow;
      expect(e.category, 'Utilities');
    });

    test('reads an amount a spreadsheet actually writes', () {
      for (final text in ['4250', '4,250.00', '₱4,250.00', ' 4250.00 ']) {
        final e = parse(row(amount: text)) as ExpenseImportRow;
        expect(e.amount, 4250.0, reason: 'failed on "$text"');
      }
    });

    test('accepts a date written the way a person types one', () {
      // 25/12 cannot be a month, so it is read day-first.
      final e = parse(row(date: '25/12/2025')) as ExpenseImportRow;
      expect(e.date, DateTime(2025, 12, 25));
    });
  });

  group('refuses', () {
    test('a category that is not in the catalogue', () {
      // The typo that silently splits a figure the Director reads as a
      // total.
      final issue = parse(row(category: 'Utilties')) as ImportIssue;
      expect(issue.message, contains('Utilties'));
      expect(issue.message, contains('Utilities'));
    });

    test('an unreadable date', () {
      expect(parse(row(date: 'last Tuesday')), isA<ImportIssue>());
    });

    test('a date that does not exist', () {
      // DateTime would roll 31 February into 3 March without complaint.
      expect(parse(row(date: '2026-02-31')), isA<ImportIssue>());
    });

    test('a date in the future', () {
      final nextYear = DateTime.now().year + 1;
      final issue = parse(row(date: '$nextYear-01-05')) as ImportIssue;
      expect(issue.message, contains('future'));
    });

    test('a zero or negative amount', () {
      expect(parse(row(amount: '0')), isA<ImportIssue>());
      expect(parse(row(amount: '-500')), isA<ImportIssue>());
    });

    test('an empty description', () {
      expect(parse(row(description: '  ')), isA<ImportIssue>());
    });

    test('a row already in the ledger', () {
      // The whole file pasted in a second time is the mistake this
      // catches, and doubling a month of spending is hard to notice
      // afterwards.
      final existing = [
        Expense(
          id: 'exp_1',
          category: 'Utilities',
          description: 'Meralco bill',
          amount: 4250.00,
          date: DateTime(2026, 3, 7),
          recordedByName: 'Corazon Buenaventura',
        ),
      ];
      final issue = parse(row(), existing: existing) as ImportIssue;
      expect(issue.message, contains('already in the ledger'));
    });

    test('the same row twice within one file', () {
      final seen = <String>{};
      expect(parse(row(), seen: seen), isA<ExpenseImportRow>());
      final issue = parse(row(), seen: seen) as ImportIssue;
      expect(issue.message, contains('appears earlier'));
    });
  });

  test('today is not the future', () {
    // An expense entered this morning carries the current time, and a
    // naive comparison against now() would reject a row dated today.
    final today = DateTime.now();
    final text = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(parse(row(date: text)), isA<ExpenseImportRow>());
  });
}
