import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/domain/entities/receipt_booklet.dart';
import 'package:logicclass/features/payments/domain/entities/receipt_series.dart';

/// Accounting for every number in a BIR booklet.
///
/// The column that matters is the one nobody has today: not "what did we
/// issue" but "what can we not account for". Every case here is a way
/// that column could be quietly wrong, which is the only way it could be
/// worse than not having it.
void main() {
  ReceiptBooklet booklet({int first = 1, int last = 10, String prefix = 'OR-'}) =>
      ReceiptBooklet(
        id: 'b1',
        prefix: prefix,
        firstNumber: first,
        lastNumber: last,
        digits: 4,
        registeredOn: DateTime(2026, 6, 1),
        registeredByName: 'Grace Mendoza',
      );

  Payment payment(int? or, {double amount = 1000, String? refundOf}) => Payment(
        id: 'pay$or',
        studentId: 'stu1',
        amount: amount,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
        receiptNumber: 'RC-2026-000001',
        officialReceiptNo: or,
        collectedByName: 'Joel Bautista',
        status: PaymentStatus.completed,
        refundOf: refundOf,
        createdAt: DateTime(2026, 6, 10),
      );

  group('reading a number off the paper', () {
    test('takes the digits, however they were typed', () {
      expect(ReceiptBooklet.parseNumber('42'), 42);
      expect(ReceiptBooklet.parseNumber('0042'), 42);
      expect(ReceiptBooklet.parseNumber('OR-0042'), 42);
      expect(ReceiptBooklet.parseNumber('  OR 0042 '), 42);
    });

    test('gives back nothing when there are no digits', () {
      expect(ReceiptBooklet.parseNumber('OR-'), isNull);
      expect(ReceiptBooklet.parseNumber(''), isNull);
    });

    test('formats back to the printed width', () {
      expect(booklet().format(42), 'OR-0042');
    });
  });

  group('a booklet used in order', () {
    test('every number used is issued, and none is unaccounted', () {
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(2), payment(3)],
      );
      expect(series.issued.length, 3);
      expect(series.gapLabels, isEmpty);
      expect(series.highestUsed, 3);
      expect(series.nextExpected, 4);
      expect(series.collected, 3000);
    });

    test('an untouched booklet expects its first number', () {
      final series = reconcileSeries(booklet: booklet(), payments: const []);
      expect(series.highestUsed, isNull);
      expect(series.nextExpected, 1);
      expect(series.gapLabels, isEmpty,
          reason: 'blank paper in a drawer is not a gap');
    });

    test('a full booklet expects nothing further', () {
      final series = reconcileSeries(
        booklet: booklet(first: 1, last: 3),
        payments: [payment(1), payment(2), payment(3)],
      );
      expect(series.nextExpected, isNull);
    });
  });

  group('the column that matters', () {
    test('a hole in the middle is reported as a gap', () {
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(2), payment(5)],
      );
      expect(series.gapLabels, ['OR-0003-OR-0004']);
    });

    test('a single missing number reads as itself, not a range', () {
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(3)],
      );
      expect(series.gapLabels, ['OR-0002']);
    });

    test('two separate holes are two entries', () {
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(3), payment(6)],
      );
      expect(series.gapLabels, ['OR-0002', 'OR-0004-OR-0005']);
    });

    test('unused numbers after the last one used are not a gap', () {
      // A booklet in progress has hundreds of unused numbers at the end
      // and none of them is a question. Reporting them would bury the
      // one that is.
      final series = reconcileSeries(
        booklet: booklet(first: 1, last: 500),
        payments: [payment(1), payment(2)],
      );
      expect(series.gapLabels, isEmpty);
    });

    test('a cancelled number closes the gap it would have left', () {
      // The whole point of recording a spoiled receipt: the number is
      // consumed, the series is continuous, and nobody has to explain it
      // twice.
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(3)],
        cancellations: [
          CancelledReceipt(
            number: 2,
            reason: 'Torn while writing',
            cancelledAt: DateTime(2026, 6, 10),
            cancelledByName: 'Joel Bautista',
          ),
        ],
      );
      expect(series.gapLabels, isEmpty);
      expect(series.cancelled.single.cancelReason, 'Torn while writing');
      expect(series.collected, 2000, reason: 'a cancelled receipt collected nothing');
    });
  });

  group('what is not counted', () {
    test('a payment with no official receipt number', () {
      // Every payment recorded before the school registered a booklet.
      // They are real payments and they are not in this series.
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(null), payment(2)],
      );
      expect(series.issued.length, 2);
      expect(series.highestUsed, 2);
    });

    test('a refund does not consume a number', () {
      // The school issues its own document for a refund. Counting it
      // against the original's number would make the series say one
      // receipt was used twice.
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(1, amount: -1000, refundOf: 'pay1')],
      );
      expect(series.issued.length, 1);
      expect(series.collected, 1000);
    });

    test('a number from another booklet', () {
      final series = reconcileSeries(
        booklet: booklet(first: 1, last: 10),
        payments: [payment(1), payment(9999)],
      );
      expect(series.issued.length, 1);
      expect(series.highestUsed, 1);
    });

    test('a cancellation outside the range', () {
      final series = reconcileSeries(
        booklet: booklet(first: 1, last: 10),
        payments: [payment(1)],
        cancellations: [
          CancelledReceipt(
            number: 9999,
            reason: 'Belongs to last year',
            cancelledAt: DateTime(2026, 6, 10),
            cancelledByName: 'Joel',
          ),
        ],
      );
      expect(series.cancelled, isEmpty);
    });

    test('two payments citing one number show it used once', () {
      // A data fault the write side guards against with a claim
      // document. If one ever reaches here, the series must still say
      // the number was used exactly once rather than counting it twice.
      final series = reconcileSeries(
        booklet: booklet(),
        payments: [payment(1), payment(1, amount: 500)],
      );
      expect(series.issued.length, 1);
      expect(series.collected, 1000, reason: 'the first write wins');
    });
  });
}
