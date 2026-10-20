import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';
import 'package:logicclass/features/payables/domain/entities/bill.dart';
import 'package:logicclass/features/payables/domain/entities/vendor.dart';

/// What the school owes, and how late.
///
/// The difference between this and an expense is the word "yet" -- and
/// almost every test here is about something staying on, or coming off,
/// an ageing report when it should.
void main() {
  final today = DateTime(2026, 10, 20);

  BillLine line(double amount, {String code = Accounts.expenseSupplies}) =>
      BillLine(
        accountCode: code,
        accountName: 'Supplies',
        description: 'Bond paper, 20 reams',
        amount: amount,
      );

  Bill bill({
    String id = 'bill_1',
    String vendorName = 'National Book Store',
    double total = 5000,
    double paid = 0,
    DateTime? due,
    DateTime? voided,
  }) =>
      Bill(
        id: id,
        vendorId: 'ven_1',
        vendorName: vendorName,
        billNumber: 'SI-99321',
        billDate: DateTime(2026, 9, 1),
        dueDate: due ?? DateTime(2026, 10, 1),
        lines: [line(total)],
        total: total,
        amountPaid: paid,
        recordedByName: 'Grace Mendoza',
        recordedAt: DateTime(2026, 9, 1),
        voidedAt: voided,
        voidReason: voided == null ? null : 'Duplicate of SI-99320',
      );

  group('terms and due dates', () {
    test('a due date is worked out from the vendor, not typed', () {
      // A date somebody has to work out by hand is a date that gets
      // typed as today.
      const net30 = Vendor(id: 'v', name: 'Supplier', paymentTermsDays: 30);
      expect(net30.dueDateFor(DateTime(2026, 9, 1)), DateTime(2026, 10, 1));
      expect(net30.termsLabel, 'Net 30');
    });

    test('cash on delivery falls due the day it is issued', () {
      const cod = Vendor(id: 'v', name: 'Sari-sari store');
      expect(cod.dueDateFor(DateTime(2026, 9, 1)), DateTime(2026, 9, 1));
      expect(cod.termsLabel, 'Cash on delivery');
    });

    test('terms that cross a month end still land on a real date', () {
      const net45 = Vendor(id: 'v', name: 'Supplier', paymentTermsDays: 45);
      expect(net45.dueDateFor(DateTime(2026, 1, 20)), DateTime(2026, 3, 6));
    });
  });

  group('what is still owed', () {
    test('is the total less what has been paid', () {
      expect(bill(total: 5000, paid: 2000).outstanding, 3000);
      expect(bill(total: 5000, paid: 0).outstanding, 5000);
    });

    test('a bill paid to the centavo is paid, not nearly paid', () {
      // Floating point leaves a residue of billionths on a bill settled
      // in three instalments, and a bill that reads as 0.0000001
      // outstanding sits on an ageing report for ever.
      const third = 5000 / 3;
      final b = bill(total: 5000, paid: third * 3);
      expect(b.isPaid, isTrue);
      expect(b.outstanding, 0);
      expect(b.effectiveStatus, BillStatus.paid);
    });

    test('an overpayment never reads as a negative debt', () {
      expect(bill(total: 5000, paid: 5200).outstanding, 0);
    });

    test('status is worked out from the numbers, not trusted', () {
      // A status field that drifted is how a paid bill stays on an
      // ageing report for a year.
      expect(bill(paid: 0).effectiveStatus, BillStatus.open);
      expect(bill(paid: 1).effectiveStatus, BillStatus.partiallyPaid);
      expect(bill(paid: 5000).effectiveStatus, BillStatus.paid);
      expect(bill(voided: today).effectiveStatus, BillStatus.void_);
    });

    test('a voided bill is settled even if nothing was paid', () {
      final v = bill(voided: today);
      expect(v.isOutstanding, isFalse);
      expect(v.isPaid, isFalse, reason: 'void is not the same as paid');
    });
  });

  group('how late', () {
    test('counts days past the due date', () {
      final b = bill(due: DateTime(2026, 10, 1));
      expect(b.daysOverdueOn(today), 19);
      expect(b.isOverdueOn(today), isTrue);
    });

    test('a bill not yet due is not overdue', () {
      final b = bill(due: DateTime(2026, 11, 1));
      expect(b.daysOverdueOn(today), lessThan(0));
      expect(b.isOverdueOn(today), isFalse);
    });

    test('a bill due today is not yet late', () {
      final b = bill(due: today);
      expect(b.daysOverdueOn(today), 0);
      expect(b.isOverdueOn(today), isFalse);
    });

    test('a paid bill is never overdue, however old', () {
      final b = bill(due: DateTime(2020, 1, 1), paid: 5000);
      expect(b.isOverdueOn(today), isFalse);
    });

    test('buckets are the ones every ageing report uses', () {
      expect(AgeingBucket.forDaysOverdue(0), AgeingBucket.current);
      expect(AgeingBucket.forDaysOverdue(-5), AgeingBucket.current);
      expect(AgeingBucket.forDaysOverdue(1), AgeingBucket.upTo30);
      expect(AgeingBucket.forDaysOverdue(30), AgeingBucket.upTo30);
      expect(AgeingBucket.forDaysOverdue(31), AgeingBucket.upTo60);
      expect(AgeingBucket.forDaysOverdue(90), AgeingBucket.upTo90);
      expect(AgeingBucket.forDaysOverdue(91), AgeingBucket.over90);
    });
  });

  group('the ageing report', () {
    test('puts each debt in its bucket and adds them up', () {
      final ageing = PayablesAgeing.from([
        bill(id: 'a', due: DateTime(2026, 11, 1), total: 1000), // not due
        bill(id: 'b', due: DateTime(2026, 10, 10), total: 2000), // 10 days
        bill(id: 'c', due: DateTime(2026, 9, 10), total: 3000), // 40 days
        bill(id: 'd', due: DateTime(2026, 5, 1), total: 4000), // 172 days
      ], asOf: today);

      expect(ageing.totals[AgeingBucket.current], 1000);
      expect(ageing.totals[AgeingBucket.upTo30], 2000);
      expect(ageing.totals[AgeingBucket.upTo60], 3000);
      expect(ageing.totals[AgeingBucket.over90], 4000);
      expect(ageing.total, 10000);
      expect(ageing.overdue, 9000, reason: 'everything but the not-yet-due');
    });

    test('counts only what is still owed on a part-paid bill', () {
      final ageing = PayablesAgeing.from(
        [bill(total: 5000, paid: 2000, due: DateTime(2026, 10, 10))],
        asOf: today,
      );
      expect(ageing.total, 3000);
    });

    test('leaves paid and voided bills off it entirely', () {
      // Both staying on is the classic way a school believes it owes
      // more than it does.
      final ageing = PayablesAgeing.from([
        bill(id: 'paid', total: 5000, paid: 5000, due: DateTime(2026, 1, 1)),
        bill(id: 'void', total: 9000, voided: today, due: DateTime(2026, 1, 1)),
        bill(id: 'real', total: 1500, due: DateTime(2026, 10, 10)),
      ], asOf: today);

      expect(ageing.total, 1500);
      expect(ageing.byVendor.values.first[AgeingBucket.upTo30], 1500);
    });

    test('groups by vendor, so it says who the school is behind with', () {
      final ageing = PayablesAgeing.from([
        bill(id: 'a', vendorName: 'National Book Store', total: 1000,
            due: DateTime(2026, 10, 10)),
        bill(id: 'b', vendorName: 'National Book Store', total: 500,
            due: DateTime(2026, 8, 1)),
        bill(id: 'c', vendorName: 'Meralco', total: 12480,
            due: DateTime(2026, 10, 15)),
      ], asOf: today);

      expect(ageing.byVendor.keys, containsAll(['National Book Store', 'Meralco']));
      expect(ageing.byVendor['National Book Store']![AgeingBucket.upTo30], 1000);
      expect(ageing.byVendor['National Book Store']![AgeingBucket.upTo90], 500);
      expect(ageing.byVendor['Meralco']![AgeingBucket.upTo30], 12480);
    });

    test('an empty payables list says so rather than showing zeroes', () {
      final ageing = PayablesAgeing.from(const [], asOf: today);
      expect(ageing.isEmpty, isTrue);
      expect(ageing.total, 0);
    });
  });

  group('recording a bill', () {
    List<BillLine> goodLines() => [line(3000), line(2000)];

    test('a well-formed bill is accepted', () {
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: 'SI-99321',
          billDate: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
          lines: goodLines(),
        ),
        isNull,
      );
    });

    test("the supplier's own number is required", () {
      // Without it there is no way to tell the supplier which bill is
      // being queried, and no way to notice the same one entered twice.
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: '   ',
          billDate: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
          lines: goodLines(),
        ),
        contains('invoice'),
      );
    });

    test('a bill with no vendor, no lines or a bad line is refused', () {
      expect(
        reasonBillCannotBeRecorded(
          vendorId: '',
          billNumber: 'SI-1',
          billDate: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
          lines: goodLines(),
        ),
        isNotNull,
      );
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: 'SI-1',
          billDate: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
          lines: const [],
        ),
        contains('at least one line'),
      );
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: 'SI-1',
          billDate: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
          lines: [line(0)],
        ),
        isNotNull,
      );
    });

    test('a bill cannot fall due before it was issued', () {
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: 'SI-1',
          billDate: DateTime(2026, 9, 10),
          dueDate: DateTime(2026, 9, 1),
          lines: goodLines(),
        ),
        contains('before it was issued'),
      );
    });

    test('a bill due the day it is issued is fine', () {
      // Cash on delivery, which is most of a school's suppliers.
      expect(
        reasonBillCannotBeRecorded(
          vendorId: 'ven_1',
          billNumber: 'SI-1',
          billDate: DateTime(2026, 9, 10),
          dueDate: DateTime(2026, 9, 10),
          lines: goodLines(),
        ),
        isNull,
      );
    });
  });

  group('paying a bill', () {
    test('a payment within what is owed is accepted', () {
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(total: 5000),
          amount: 2000,
          paidFromAccountCode: Accounts.cashInBank,
        ),
        isNull,
      );
    });

    test('settling it exactly is accepted', () {
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(total: 5000, paid: 2000),
          amount: 3000,
          paidFromAccountCode: Accounts.cashInBank,
        ),
        isNull,
      );
    });

    test('overpaying is refused, and says what is left', () {
      // Almost always a typo. Letting it through turns one mistake into
      // a wrong total on every report that sums outstanding.
      final reason = reasonPaymentCannotBeMade(
        bill: bill(total: 5000, paid: 2000),
        amount: 4000,
        paidFromAccountCode: Accounts.cashInBank,
      );
      expect(reason, contains('3000.00'));
    });

    test('a settled or voided bill takes no more money', () {
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(total: 5000, paid: 5000),
          amount: 100,
          paidFromAccountCode: Accounts.cashInBank,
        ),
        contains('already settled'),
      );
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(voided: today),
          amount: 100,
          paidFromAccountCode: Accounts.cashInBank,
        ),
        contains('voided'),
      );
    });

    test('a payment of nothing, or from nowhere, is refused', () {
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(),
          amount: 0,
          paidFromAccountCode: Accounts.cashInBank,
        ),
        isNotNull,
      );
      expect(
        reasonPaymentCannotBeMade(
          bill: bill(),
          amount: 100,
          paidFromAccountCode: '  ',
        ),
        isNotNull,
      );
    });
  });
}
