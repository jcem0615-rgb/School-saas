import 'csv.dart' show ImportIssue;

/// Works out where each expected column sits in an imported file.
///
/// Matched by name rather than by position, with extra columns ignored.
/// That is what lets an exported roster be imported straight back: the
/// export carries Student Number, Status and Balance, which the importer
/// has no use for, and under a strict positional check those three
/// columns would reject the file the app itself produced. It also
/// forgives the reordering that happens the moment somebody sorts a
/// spreadsheet by surname or drags a column somewhere more convenient.
class ImportColumns {
  ImportColumns._();

  /// Returns the index in [fileHeader] of each entry in [wanted], or an
  /// [ImportIssue] naming every column that is missing.
  ///
  /// Every missing column at once, not the first: someone fixing a file
  /// should need one more attempt, not one per absent header.
  static Object resolve(List<String> fileHeader, List<String> wanted) {
    final present = fileHeader.map((h) => h.trim().toLowerCase()).toList();
    final columns = <int>[];
    final missing = <String>[];

    for (final column in wanted) {
      final at = present.indexOf(column.trim().toLowerCase());
      if (at < 0) missing.add(column);
      columns.add(at);
    }

    if (missing.isNotEmpty) {
      return ImportIssue(
        1,
        'The file is missing ${missing.length == 1 ? "a column" : "columns"}: '
        '${missing.join(", ")}. Download the blank template to see the '
        'columns this import expects.',
      );
    }
    return columns;
  }

  /// Puts one row into the wanted order, blanking any cell the row is too
  /// short to have -- which is every trailing empty column, since neither
  /// CSV nor Excel writes them out.
  static List<String> reorder(List<String> row, List<int> columns) =>
      [for (final at in columns) at >= 0 && at < row.length ? row[at] : ''];
}
