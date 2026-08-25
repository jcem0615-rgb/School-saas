/// Reading the two cell types every importer trips over: dates and money.
///
/// A spreadsheet has no types by the time it reaches here -- Workbook
/// hands every cell over as a string, deliberately, so that a student
/// number made of digits survives the trip. That puts the burden of
/// telling 03/07/2012 from 7 March on the importer, and three importers
/// each guessing separately is three chances to guess differently about
/// the same file.
class SheetValues {
  SheetValues._();

  /// ISO first, because that is what a date cell and every export here
  /// produce. Slashed dates are read day-first only when the first number
  /// cannot be a month -- 25/12/2012 is unambiguous, 03/07/2012 is not,
  /// and guessing at the ambiguous one silently files the record under
  /// the wrong date. Month-first matches both the templates and the
  /// Philippine convention.
  static DateTime? parseDate(String text) {
    final iso = DateTime.tryParse(text);
    if (iso != null) {
      // DateTime.tryParse rolls an impossible date over instead of
      // refusing it: 2026-02-31 comes back as 3 March and 2026-13-01 as
      // January 2027, both without complaint. A spreadsheet cell that
      // says the 31st of February is a mistake somebody made, and
      // filing the record three days later is the wrong way to handle
      // it -- so the parsed date is checked back against what was
      // written.
      final digits = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text.trim());
      if (digits != null) {
        if (iso.year != int.parse(digits.group(1)!) ||
            iso.month != int.parse(digits.group(2)!) ||
            iso.day != int.parse(digits.group(3)!)) {
          return null;
        }
      }
      return DateTime(iso.year, iso.month, iso.day);
    }

    final parts = text.split(RegExp(r'[/\-.]')).where((p) => p.isNotEmpty).toList();
    if (parts.length != 3) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (a == null || b == null || year == null || year < 1900) return null;

    final (month, day) = a > 12 ? (b, a) : (a, b);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    // Rejects 31 February, which DateTime would happily roll into March.
    return parsed.month == month && parsed.day == day ? parsed : null;
  }

  /// A number as a spreadsheet actually writes one.
  ///
  /// Excel formats a currency column and the cell arrives as "₱1,250.00";
  /// a bookkeeper types "1 250"; an accounting format writes a negative
  /// as "(250.00)". All three are the same number, and refusing them
  /// sends someone back to retype a column that was never wrong.
  ///
  /// Currency symbols are stripped rather than checked. This app is one
  /// school in one country, and a peso sign in a peso column carries no
  /// information -- while rejecting the row over it would be baffling.
  static double? parseAmount(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;

    var negative = false;
    if (t.startsWith('(') && t.endsWith(')')) {
      negative = true;
      t = t.substring(1, t.length - 1);
    }

    t = t.replaceAll(RegExp(r'[₱$,\s]'), '');
    if (t.startsWith('-')) {
      negative = true;
      t = t.substring(1);
    }
    if (t.isEmpty) return null;

    final value = double.tryParse(t);
    if (value == null) return null;
    return negative ? -value : value;
  }

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
