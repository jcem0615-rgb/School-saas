import '../../../../core/data_transfer/csv.dart' show ImportIssue;
import '../../../../core/data_transfer/sheet_values.dart';
import '../../domain/entities/expense.dart';

/// Turns spreadsheet rows into expenses the Director could have typed.
///
/// The ledger is what the school's own budget reporting is built on, so
/// the checks here are about not letting a paste from a bookkeeper's
/// workbook quietly distort it: a category nobody uses splits a report in
/// two, a zero amount is a row somebody forgot to finish, and the same
/// file imported twice doubles the month.
///
/// Recorded By is deliberately not importable. It names who entered the
/// spending, the server stamps it from the signed-in user, and a column
/// that let a file claim otherwise would put someone else's name against
/// money they never recorded.
class ExpenseImport {
  ExpenseImport._();

  /// Validates one spreadsheet row into something recordable.
  ///
  /// [categories] is the school's catalogue, [existing] the ledger as it
  /// stands, and [seen] carries the keys of rows already accepted from
  /// this same file.
  static Object? parseRow({
    required List<String> row,
    required int rowNumber,
    required List<String> categories,
    required List<Expense> existing,
    required Set<String> seen,
  }) {
    final dateText = row[0].trim();
    final categoryText = row[1].trim();
    final description = row[2].trim();
    final amountText = row[3].trim();

    if (dateText.isEmpty) return ImportIssue(rowNumber, 'Date is required.');
    final date = SheetValues.parseDate(dateText);
    if (date == null) {
      return ImportIssue(
        rowNumber,
        'Could not read the date "$dateText". Use a date cell or write it '
        'as 2026-03-07.',
      );
    }
    // A ledger records what has been spent. A future date is a mis-typed
    // year far more often than it is a plan, and it lands the row in a
    // month nobody is reconciling yet.
    if (date.isAfter(_endOfToday())) {
      return ImportIssue(rowNumber, 'Date $dateText is in the future.');
    }

    if (categoryText.isEmpty) return ImportIssue(rowNumber, 'Category is required.');
    final category = categories
        .where((c) => c.toLowerCase() == categoryText.toLowerCase())
        .firstOrNull;
    // Matched against the catalogue rather than taken as typed. A free
    // category column looks harmless until "Utilties" becomes its own
    // line in the expense report, splitting a figure the Director is
    // reading as a total.
    if (category == null) {
      return ImportIssue(
        rowNumber,
        'Unknown category "$categoryText". Use one of: ${categories.join(', ')}.',
      );
    }

    if (description.isEmpty) return ImportIssue(rowNumber, 'Description is required.');

    if (amountText.isEmpty) return ImportIssue(rowNumber, 'Amount is required.');
    final amount = SheetValues.parseAmount(amountText);
    if (amount == null) {
      return ImportIssue(rowNumber, 'Could not read the amount "$amountText".');
    }
    if (amount <= 0) {
      return ImportIssue(
        rowNumber,
        'Amount must be more than zero. A refund is recorded on its own, '
        'not as a negative expense.',
      );
    }

    // Date, category, description and amount all matching is what a file
    // imported twice looks like -- and doubling a month of spending is
    // both easy to do and hard to notice afterwards. Two genuinely
    // identical expenses on one day do happen; saying which is which in
    // the description is the way through, and is worth more in the
    // ledger than a bare duplicate anyway.
    final key = '${SheetValues.isoDate(date)}|${category.toLowerCase()}|'
        '${description.toLowerCase()}|${amount.toStringAsFixed(2)}';
    if (existing.any((e) => _keyOf(e) == key)) {
      return ImportIssue(
        rowNumber,
        '"$description" on ${SheetValues.isoDate(date)} is already in the '
        'ledger for the same amount.',
      );
    }
    if (!seen.add(key)) {
      return ImportIssue(rowNumber, '"$description" appears earlier in this file.');
    }

    return ExpenseImportRow(
      category: category,
      description: description,
      amount: amount,
      date: date,
    );
  }

  static String _keyOf(Expense e) =>
      '${SheetValues.isoDate(e.date)}|${e.category.toLowerCase()}|'
      '${e.description.toLowerCase()}|${e.amount.toStringAsFixed(2)}';

  /// Today counts as past. An expense entered this morning carries the
  /// current time, and comparing against `DateTime.now()` would reject a
  /// row dated today for being a few hours ahead of it.
  static DateTime _endOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }
}

/// One validated spreadsheet row, ready for `createExpense`.
class ExpenseImportRow {
  final String category;
  final String description;
  final double amount;
  final DateTime date;

  const ExpenseImportRow({
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
  });
}
