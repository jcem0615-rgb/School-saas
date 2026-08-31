import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/discount.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/usecases/fee_usecases.dart';

/// What a discount does to what a family owes.
///
/// The failure modes here are all ways of getting money wrong in public:
/// discounting a fee the school never meant to discount, charging less
/// than nothing, or showing a family a figure that does not match the
/// paper they were handed.
void main() {
  const fees = [
    FeeItem(label: 'Tuition Fee', amount: 20000, category: FeeCategory.tuition),
    FeeItem(label: 'Miscellaneous Fee', amount: 4000, category: FeeCategory.miscellaneous),
    FeeItem(label: 'Handbook', amount: 300, category: FeeCategory.other),
  ];

  Discount discount({
    required double amount,
    double? percentage,
    FeeCategory? appliesTo,
    DiscountKind kind = DiscountKind.sibling,
    String label = 'Sibling discount',
  }) =>
      Discount(
        kind: kind,
        label: label,
        amount: amount,
        percentage: percentage,
        appliesTo: appliesTo,
        approvedByName: 'Grace Mendoza',
      );

  group('what a percentage comes to', () {
    test('of tuition only, which is what a school usually means', () {
      // The miscellaneous bundle is largely money passed through to third
      // parties. A discount that quietly included it gives away more than
      // the school decided to.
      expect(
        discountAmountFor(items: fees, percentage: 10, appliesTo: FeeCategory.tuition),
        2000,
      );
    });

    test('of everything, when the school says everything', () {
      expect(discountAmountFor(items: fees, percentage: 10), 2430);
    });

    test('rounds to the centavo rather than carrying a fraction', () {
      expect(
        discountAmountFor(items: fees, percentage: 7.5, appliesTo: FeeCategory.other),
        22.5,
      );
    });

    test('a category nothing falls under comes to nothing', () {
      const tuitionOnly = [FeeItem(label: 'Tuition', amount: 20000, category: FeeCategory.tuition)];
      expect(
        discountAmountFor(
            items: tuitionOnly, percentage: 50, appliesTo: FeeCategory.miscellaneous),
        0,
      );
    });
  });

  group('what the family is charged', () {
    Assessment assessed(List<Discount> discounts) => Assessment(
          id: 'a1',
          studentId: 'stu1',
          studentName: 'Trisha Mercado',
          schoolYear: '2026-2027',
          items: fees,
          discounts: discounts,
          assessedByName: 'Joel Bautista',
          assessedAt: DateTime(2026, 6, 1),
        );

    test('the published fees, when nothing was granted', () {
      final assessment = assessed(const []);
      expect(assessment.grossTotal, 24300);
      expect(assessment.discountTotal, 0);
      expect(assessment.total, 24300);
    });

    test('the fees less what was taken off', () {
      // `total` nets rather than sitting beside a gross figure, because
      // every existing caller -- the balance, the breakdown, collections
      // -- means "what does this family owe".
      final assessment = assessed([discount(amount: 2000, percentage: 10, appliesTo: FeeCategory.tuition)]);
      expect(assessment.total, 22300);
      expect(assessment.effectiveTotal, 22300);
    });

    test('two discounts both come off', () {
      final assessment = assessed([
        discount(amount: 2000),
        discount(amount: 500, kind: DiscountKind.earlyBird, label: 'Early payment'),
      ]);
      expect(assessment.discountTotal, 2500);
      expect(assessment.total, 21800);
    });

    test('a full waiver charges nothing, not less than nothing', () {
      final assessment = assessed([discount(amount: 24300)]);
      expect(assessment.total, 0);
    });

    test('a hand-edited over-grant still cannot pay a family to enrol', () {
      // Refused when granted; clamped here as well, because a document
      // corrected by hand is not a document that went through the
      // callable.
      final assessment = assessed([discount(amount: 30000)]);
      expect(assessment.total, 0);
    });

    test('a voided assessment contributes nothing either way', () {
      final assessment = Assessment(
        id: 'a1',
        studentId: 'stu1',
        studentName: 'Trisha Mercado',
        schoolYear: '2026-2027',
        items: fees,
        discounts: [discount(amount: 2000)],
        assessedByName: 'Joel Bautista',
        assessedAt: DateTime(2026, 6, 1),
        voidedAt: DateTime(2026, 7, 1),
      );
      expect(assessment.effectiveTotal, 0);
    });
  });

  group('how the line reads', () {
    test('names the rate and what it was taken against', () {
      expect(
        discount(amount: 2000, percentage: 10, appliesTo: FeeCategory.tuition).displayLine,
        'Sibling discount (10% of tuition)',
      );
    });

    test('a flat amount reads as itself', () {
      expect(discount(amount: 2000).displayLine, 'Sibling discount');
    });

    test('drops a trailing zero so 10% is not 10.00%', () {
      expect(
        discount(amount: 100, percentage: 12.5).displayLine,
        'Sibling discount (12.5%)',
      );
    });
  });

  group('what is refused before it is granted', () {
    test('nothing at all is fine', () {
      expect(checkDiscounts(const [], 24300), isNull);
    });

    test('a discount with no name', () {
      expect(
        checkDiscounts([discount(amount: 100, label: '   ')], 24300)?.message,
        contains('needs a name'),
      );
    });

    test('a rate above 100 per cent', () {
      expect(
        checkDiscounts([discount(amount: 100, percentage: 120)], 24300)?.message,
        contains('between 0 and 100'),
      );
    });

    test('more given away than charged', () {
      expect(
        checkDiscounts([discount(amount: 30000)], 24300)?.message,
        contains('cannot charge less than nothing'),
      );
    });

    test('waiving the exact total is allowed', () {
      // A full scholarship is a real thing and must not be refused.
      expect(checkDiscounts([discount(amount: 24300)], 24300), isNull);
    });
  });

  group('the plan a discounted family is put on', () {
    test('adds up to the net, not the published fees', () {
      // The join between this feature and instalments. Checking the plan
      // against the gross would refuse every discounted family a payment
      // plan at all.
      final net = 24300.0 - 2000.0;
      expect(checkInstallments(const [], net), isNull);
    });
  });
}
