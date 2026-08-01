/// Minimal RFC 4180 CSV reader/writer.
///
/// Hand-rolled rather than pulled in as a dependency because the whole
/// surface needed here is "quote fields that contain a comma, quote or
/// newline, and read them back" -- and because a school's data is full of
/// exactly those: names with commas, addresses with newlines, remarks with
/// quotes. Getting that wrong silently corrupts an import, so it is worth
/// having the rules visible and tested rather than assumed.
class Csv {
  Csv._();

  static String _escapeField(String value) {
    final needsQuoting =
        value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r');
    if (!needsQuoting) return value;
    // A literal quote is doubled inside a quoted field.
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Serialises [rows] with [headers] as the first line.
  static String encode(List<String> headers, List<List<String>> rows) {
    final buffer = StringBuffer()..writeln(headers.map(_escapeField).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_escapeField).join(','));
    }
    return buffer.toString();
  }

  /// Parses [input] into rows of fields, including the header row.
  ///
  /// Tolerates CRLF, a trailing newline, and quoted fields containing
  /// commas or newlines. Returns an empty list for empty input rather than
  /// a row of one empty string, so callers can check `isEmpty` meaningfully.
  static List<List<String>> decode(String input) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    var fieldWasQuoted = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (inQuotes) {
        if (char == '"') {
          // A doubled quote inside a quoted field is a literal quote.
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      switch (char) {
        case '"':
          inQuotes = true;
          fieldWasQuoted = true;
        case ',':
          row.add(field.toString());
          field = StringBuffer();
          fieldWasQuoted = false;
        case '\r':
          break; // CRLF: the \n does the work
        case '\n':
          row.add(field.toString());
          field = StringBuffer();
          // Skip blank lines, which trailing newlines and stray CRLFs
          // produce and which are never meaningful data.
          if (!(row.length == 1 && row.first.isEmpty && !fieldWasQuoted)) {
            rows.add(row);
          }
          row = <String>[];
          fieldWasQuoted = false;
        default:
          field.write(char);
      }
    }

    // Whatever is left when the input ends without a trailing newline.
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (!(row.length == 1 && row.first.isEmpty && !fieldWasQuoted)) {
        rows.add(row);
      }
    }
    return rows;
  }
}

/// One problem found while importing, tied to the line it came from.
///
/// Row numbers are 1-based and count the header, so they match what the
/// user sees in a spreadsheet -- an error reported for "row 4" is on the
/// fourth line of their file, not the fifth.
class ImportIssue {
  final int row;
  final String message;
  const ImportIssue(this.row, this.message);

  @override
  String toString() => 'Row $row: $message';
}

/// The outcome of parsing an import file.
///
/// Deliberately carries both the valid records and the issues rather than
/// throwing on the first bad row: a user fixing a 200-row spreadsheet
/// needs every problem at once, not one per attempt.
class ImportResult<T> {
  final List<T> records;
  final List<ImportIssue> issues;
  const ImportResult({required this.records, required this.issues});

  bool get hasIssues => issues.isNotEmpty;
  bool get isEmpty => records.isEmpty && issues.isEmpty;
}
