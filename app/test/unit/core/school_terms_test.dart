import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/school_terms.dart';

/// One list of quarter names, and the shorthands that resolve onto it.
///
/// The defect behind this: the class record offered "1st Quarter" from a
/// dropdown, the grade submission dialog shipped a free-text box
/// defaulting to "Q1", and every query on `term` is an equality match. A
/// mark entered in one screen was invisible in the other. Nothing
/// errored -- it was saved, confirmed, and simply never appeared.
void main() {
  test('there are four quarters, named the way the dropdowns name them', () {
    expect(schoolTerms, [
      '1st Quarter',
      '2nd Quarter',
      '3rd Quarter',
      '4th Quarter',
    ]);
  });

  group('canonicalTerm', () {
    test('leaves a canonical name alone', () {
      for (final term in schoolTerms) {
        expect(canonicalTerm(term), term);
      }
    });

    test('resolves the shorthands people actually type', () {
      expect(canonicalTerm('Q1'), '1st Quarter');
      expect(canonicalTerm('q1'), '1st Quarter');
      expect(canonicalTerm('1'), '1st Quarter');
      expect(canonicalTerm('1st'), '1st Quarter');
      expect(canonicalTerm('First Quarter'), '1st Quarter');
      expect(canonicalTerm('Quarter 4'), '4th Quarter');
      expect(canonicalTerm('  q2  '), '2nd Quarter');
    });

    test('matches a canonical name whatever its case', () {
      expect(canonicalTerm('1ST QUARTER'), '1st Quarter');
      expect(canonicalTerm('2nd quarter'), '2nd Quarter');
    });

    test('keeps a name it does not recognise', () {
      // A school running its own term names has to be able to. Rewriting
      // "Prelim" to a quarter would be this software deciding how a
      // school divides its year.
      expect(canonicalTerm('Prelim'), 'Prelim');
      expect(canonicalTerm('Semester 1'), 'Semester 1');
    });

    test('an empty term stays empty rather than becoming the first quarter', () {
      // Guessing here would file an unlabelled mark under a real quarter,
      // where it would be counted and nobody would know to look.
      expect(canonicalTerm(''), '');
      expect(canonicalTerm('   '), '');
    });
  });
}
