/// One report, in the only shape this module has.
///
/// Every report here -- enrollment, collections, attendance, grades --
/// comes out as a title, a handful of headline figures and a table. That
/// is not a simplification of what schools report; it is what they
/// report. Fixing the shape means the spreadsheet export, the printed
/// PDF and the on-screen table are each written once rather than four
/// times, and a fifth report costs a builder function and nothing else.
class ReportTable {
  final String title;

  /// What the figures cover: a school year, a date range, a division.
  final String subtitle;

  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// The two or three numbers somebody actually came for. A division
  /// head opening an enrollment report wants the roll first and the
  /// breakdown second.
  final List<ReportStat> headline;

  /// What the table does not say. Printed under it and carried into the
  /// export, because a caveat that lives only on screen is a caveat that
  /// gets separated from the figures the moment anyone mails the file.
  final String? note;

  /// What the reader can narrow this report by, if anything, and the
  /// values on offer.
  ///
  /// The values come out of the data rather than out of a fixed list --
  /// terms are free text in this system, so the only honest set of
  /// choices is the set somebody actually used. Offering a typed field
  /// instead would mean a report that silently returns nothing because
  /// the office writes "1st Quarter" and the reader typed "Q1".
  final String? filterLabel;
  final List<String> filterOptions;

  const ReportTable({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    this.headline = const [],
    this.note,
    this.filterLabel,
    this.filterOptions = const [],
  });

  bool get isEmpty => rows.isEmpty;

  List<String> get headers => [for (final column in columns) column.label];

  /// The table as plain rows, for the workbook writer.
  List<List<String>> get cellRows => [for (final row in rows) row.cells];
}

class ReportColumn {
  final String label;

  /// Right-aligned on screen and in print. Not a formatting preference:
  /// a column of figures that does not line up on the decimal point is
  /// one nobody can scan down.
  final bool numeric;

  const ReportColumn(this.label, {this.numeric = false});
}

class ReportRow {
  final List<String> cells;

  /// A totals or subtotal row. Kept as an ordinary row rather than a
  /// separate field so that the export writes it too -- a spreadsheet
  /// whose total row went missing in the export is worse than one with
  /// no total at all, because the reader does not know it is absent.
  final bool isTotal;

  const ReportRow(this.cells, {this.isTotal = false});
}

class ReportStat {
  final String label;
  final String value;

  /// A second line under the value: "of 240 assessed", "across 4 divisions".
  final String? caption;

  const ReportStat({required this.label, required this.value, this.caption});
}
