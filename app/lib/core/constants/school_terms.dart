/// The four quarters a Philippine school year is graded in.
///
/// One list, because the alternative is what this replaces: the class
/// record offered "1st Quarter" from a dropdown and the grade submission
/// dialog shipped a free-text box defaulting to "Q1". Both wrote to the
/// same `term` field, every query on it is an equality match, and so a
/// mark entered in one screen was invisible in the other -- filed under a
/// quarter that, as far as the database was concerned, was a different
/// quarter entirely.
///
/// Nothing errored. The mark was saved, the screen said so, and it simply
/// never appeared. `report_table.dart` names this exact hazard in a
/// comment -- "the office writes 1st Quarter and the reader typed Q1" --
/// which is how a known failure survives: written down in one place,
/// unguarded in the write path.
///
/// Free text is still what the *storage* holds, because a school that
/// runs its own term names has to be able to, and a spreadsheet import
/// can carry anything. What this fixes is that nothing in the app hands a
/// teacher a way to invent one by accident.
const schoolTerms = <String>[
  '1st Quarter',
  '2nd Quarter',
  '3rd Quarter',
  '4th Quarter',
];

/// Maps the shorthands people actually type onto the canonical names.
///
/// For the import, where the column is whatever the spreadsheet says. A
/// row reading "Q1" or "1st" or "first quarter" means the first quarter
/// and should land there rather than founding a quarter of its own.
/// Anything it does not recognise is returned untouched: a school with
/// genuinely different term names keeps them.
String canonicalTerm(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  for (final term in schoolTerms) {
    if (term.toLowerCase() == trimmed.toLowerCase()) return term;
  }
  const shorthands = {
    '1': 0, 'q1': 0, '1st': 0, 'first': 0, 'first quarter': 0, 'quarter 1': 0,
    '2': 1, 'q2': 1, '2nd': 1, 'second': 1, 'second quarter': 1, 'quarter 2': 1,
    '3': 2, 'q3': 2, '3rd': 2, 'third': 2, 'third quarter': 2, 'quarter 3': 2,
    '4': 3, 'q4': 3, '4th': 3, 'fourth': 3, 'fourth quarter': 3, 'quarter 4': 3,
  };
  final index = shorthands[trimmed.toLowerCase()];
  return index == null ? trimmed : schoolTerms[index];
}
