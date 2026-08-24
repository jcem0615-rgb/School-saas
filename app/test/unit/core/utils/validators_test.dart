import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts multi-label domains', () {
      // Regression: the original pattern ended in `\.[a-zA-Z]{2,}$` with no
      // allowance for intermediate labels, so every `*.edu.ph` address was
      // rejected -- which is most of this product's users. Nothing caught
      // it because the only address the validator was exercised against in
      // isolation was a two-label one.
      expect(Validators.email('jane@school.edu.ph'), isNull);
      expect(Validators.email('registrar@stnicholas.edu.ph'), isNull);
      expect(Validators.email('a@b.co.uk'), isNull);
    });

    test('accepts ordinary two-label domains', () {
      expect(Validators.email('owner@demo.ph'), isNull);
      expect(Validators.email('someone@example.com'), isNull);
      expect(Validators.email('first.last+tag@example.com'), isNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('missing@tld'), isNotNull);
      expect(Validators.email('@example.com'), isNotNull);
      expect(Validators.email('spaces in@example.com'), isNotNull);
      expect(Validators.email('trailing@example.'), isNotNull);
    });

    test('rejects empty or whitespace-only input', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('   '), isNotNull);
    });

    test('ignores surrounding whitespace', () {
      expect(Validators.email('  jane@school.edu.ph  '), isNull);
    });
  });

  group('Validators.password', () {
    test('requires at least 8 characters with a letter and a digit', () {
      expect(Validators.password('demo1234'), isNull);
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('alllettershere'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password(''), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('matches only an identical value', () {
      expect(Validators.confirmPassword('demo1234', 'demo1234'), isNull);
      expect(Validators.confirmPassword('demo1234', 'Demo1234'), isNotNull);
    });
  });
}
