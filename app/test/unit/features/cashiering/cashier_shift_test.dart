import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/cashiering/domain/entities/cashier_shift.dart';

/// A cashier's drawer, from opening to counting.
///
/// "The cashier is trustworthy" is not a control, it is a hope. These
/// tests are about the arithmetic that replaces it, and about a
/// difference never being allowed to pass silently.
void main() {
  final opened = DateTime(2026, 10, 20, 7, 30);

  CashierShift shift({
    double float = 2000,
    DateTime? closedAt,
    double? counted,
    double? expected,
  }) =>
      CashierShift(
        id: 'shift_1',
        cashierUid: 'u_registrar',
        cashierName: 'Rosario Aguilar',
        openedAt: opened,
        openingFloat: float,
        closedAt: closedAt,
        countedAmount: counted,
        expectedAmount: expected,
      );

  group('what should be in the drawer', () {
    test('is the float plus what came in', () {
      const reckoning = ShiftReckoning(
        openingFloat: 2000,
        cashCollected: 48500,
        cashRefunded: 0,
        receiptCount: 23,
      );
      expect(reckoning.expected, 50500);
      expect(reckoning.toDeposit, 48500,
          reason: 'the float stays for tomorrow');
    });

    test('refunds come back out of the same money', () {
      // A shift that ignored them would read short by exactly the
      // refunds, every time one happened.
      const reckoning = ShiftReckoning(
        openingFloat: 2000,
        cashCollected: 48500,
        cashRefunded: 1500,
        receiptCount: 24,
      );
      expect(reckoning.expected, 49000);
      expect(reckoning.toDeposit, 47000);
    });

    test('a drawer that took nothing still holds its float', () {
      const reckoning = ShiftReckoning(
        openingFloat: 2000,
        cashCollected: 0,
        cashRefunded: 0,
        receiptCount: 0,
      );
      expect(reckoning.expected, 2000);
      expect(reckoning.toDeposit, 0);
    });

    test('works out the variance against a count', () {
      const reckoning = ShiftReckoning(
        openingFloat: 2000,
        cashCollected: 48500,
        cashRefunded: 0,
        receiptCount: 23,
      );
      expect(reckoning.varianceAgainst(50500), 0);
      expect(reckoning.varianceAgainst(50380), -120);
      expect(reckoning.varianceAgainst(50505), 5);
    });
  });

  group('an open drawer', () {
    test('has no variance, because nobody has counted it', () {
      // Showing zero would say it had been checked.
      final s = shift();
      expect(s.isOpen, isTrue);
      expect(s.variance, isNull);
      expect(s.isBalanced, isFalse);
      expect(s.varianceLabel(), 'Not counted');
    });

    test('holds everything from the moment it opened until now', () {
      final s = shift();
      expect(s.holds(opened), isTrue, reason: 'the opening instant counts');
      expect(s.holds(opened.add(const Duration(hours: 3))), isTrue);
      expect(s.holds(opened.subtract(const Duration(minutes: 1))), isFalse);
      expect(s.holds(DateTime(2030)), isTrue, reason: 'an open shift runs on');
    });
  });

  group('a counted drawer', () {
    test('short reads short, and says by how much', () {
      final s = shift(
        closedAt: DateTime(2026, 10, 20, 17, 0),
        counted: 50380,
        expected: 50500,
      );
      expect(s.variance, -120);
      expect(s.isShort, isTrue);
      expect(s.isOver, isFalse);
      expect(s.varianceLabel(), 'Short 120.00');
    });

    test('over reads over', () {
      final s = shift(
        closedAt: DateTime(2026, 10, 20, 17, 0),
        counted: 50505,
        expected: 50500,
      );
      expect(s.isOver, isTrue);
      expect(s.varianceLabel(), 'Over 5.00');
    });

    test('balanced is balanced, to the centavo', () {
      // Floating point leaves residue on anything divided up, and a
      // drawer reported short by a billionth of a peso is a report
      // nobody would believe twice.
      final s = shift(
        closedAt: DateTime(2026, 10, 20, 17, 0),
        counted: 50500.000000001,
        expected: 50500,
      );
      expect(s.isBalanced, isTrue);
      expect(s.isShort, isFalse);
      expect(s.isOver, isFalse);
      expect(s.varianceLabel(), 'Balanced');
    });

    test('stops holding receipts written after it closed', () {
      final closed = DateTime(2026, 10, 20, 17, 0);
      final s = shift(closedAt: closed, counted: 1, expected: 1);
      expect(s.holds(closed), isTrue, reason: 'the closing instant counts');
      expect(s.holds(closed.add(const Duration(seconds: 1))), isFalse);
    });

    test('is closed', () {
      final s = shift(closedAt: DateTime(2026, 10, 20, 17, 0));
      expect(s.status, ShiftStatus.closed);
      expect(s.isOpen, isFalse);
    });
  });

  group('opening one', () {
    test('a first drawer with a counted float is fine', () {
      expect(
        reasonShiftCannotOpen(openShift: null, openingFloat: 2000),
        isNull,
      );
    });

    test('a float of nothing is allowed', () {
      // Some schools start the day with an empty drawer.
      expect(reasonShiftCannotOpen(openShift: null, openingFloat: 0), isNull);
    });

    test('a second drawer for the same person is refused', () {
      // Two open at once means every receipt belongs to both and the
      // reckoning is meaningless.
      final reason =
          reasonShiftCannotOpen(openShift: shift(), openingFloat: 2000);
      expect(reason, contains('already a drawer open'));
      expect(reason, contains('07:30'), reason: 'say which one');
    });

    test('a negative float is refused', () {
      expect(
        reasonShiftCannotOpen(openShift: null, openingFloat: -1),
        isNotNull,
      );
    });
  });

  group('closing one', () {
    String? closing({
      double counted = 50500,
      double expected = 50500,
      String note = '',
      CashierShift? on,
    }) =>
        reasonShiftCannotClose(
          shift: on ?? shift(),
          countedAmount: counted,
          expectedAmount: expected,
          varianceNote: note,
        );

    test('a drawer that balances needs no explanation', () {
      expect(closing(), isNull);
    });

    test('a difference with no explanation is refused, and says which way', () {
      // It does not have to be a good reason -- "two hundred short, no
      // idea" is a far better record than silence -- but it has to be a
      // reason.
      final short = closing(counted: 50300, expected: 50500);
      expect(short, contains('short'));
      expect(short, contains('200.00'));

      final over = closing(counted: 50700, expected: 50500);
      expect(over, contains('over'));
    });

    test('a difference with an explanation goes through', () {
      expect(
        closing(counted: 50300, expected: 50500, note: 'Gave wrong change this morning'),
        isNull,
      );
    });

    test('a few words is not an explanation', () {
      expect(closing(counted: 50300, expected: 50500, note: 'x'), isNotNull);
      expect(closing(counted: 50300, expected: 50500, note: '   '), isNotNull);
    });

    test('a drawer already closed takes no second count', () {
      expect(
        closing(on: shift(closedAt: DateTime(2026, 10, 20, 17, 0))),
        contains('already closed'),
      );
    });

    test('a negative count is refused', () {
      expect(closing(counted: -1, expected: 0, note: 'nonsense'), isNotNull);
    });

    test('a centavo of drift needs no explanation', () {
      expect(closing(counted: 50500.000000001, expected: 50500), isNull);
    });
  });
}
