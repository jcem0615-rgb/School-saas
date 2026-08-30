import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/entities/installment.dart';

/// The arithmetic behind "who is overdue and by how much".
///
/// Every case here is one a school would recognise, because the ways
/// this can be wrong are all ways of accusing a family of not paying.
void main() {
  DateTime day(int month, int dayOfMonth) => DateTime(2026, month, dayOfMonth);

  BillingSchedule quarterly() => BillingSchedule([
        Installment(label: 'Upon enrolment', dueDate: day(6, 1), amount: 10000),
        Installment(label: 'August', dueDate: day(8, 5), amount: 5000),
        Installment(label: 'October', dueDate: day(10, 5), amount: 5000),
        Installment(label: 'December', dueDate: day(12, 5), amount: 5000),
      ]);

  group('what should have arrived', () {
    test('nothing, before the first due date', () {
      expect(quarterly().amountDueBy(day(5, 31)), 0);
    });

    test('a payment due today is due today, not tomorrow', () {
      // The off-by-one that would have a school chasing a family on the
      // morning of the day they were told to pay.
      expect(quarterly().amountDueBy(day(6, 1)), 10000);
    });

    test('accumulates as the year goes on', () {
      expect(quarterly().amountDueBy(day(8, 5)), 15000);
      expect(quarterly().amountDueBy(day(10, 4)), 15000);
      expect(quarterly().amountDueBy(day(12, 31)), 25000);
    });
  });

  group('how far behind', () {
    test('a family who has paid nothing owes what has fallen due', () {
      expect(quarterly().overdueAmount(paid: 0, asOf: day(8, 6)), 15000);
    });

    test('a family who paid on time owes nothing', () {
      expect(quarterly().overdueAmount(paid: 15000, asOf: day(8, 6)), 0);
    });

    test('paying ahead is not a debt owed the other way', () {
      // The whole year settled in June. Never negative -- a report that
      // showed -10,000 overdue would be read as a credit the school owes.
      expect(quarterly().overdueAmount(paid: 25000, asOf: day(6, 2)), 0);
    });

    test('an early payment counts against the next instalment', () {
      // A family who paid 15,000 in June is not overdue in August, even
      // though the August instalment has no payment "against" it. Money
      // is not earmarked, and treating it as though it were is how a
      // school chases somebody who is ahead.
      expect(quarterly().overdueAmount(paid: 15000, asOf: day(8, 10)), 0);
    });

    test('a partial payment leaves the difference', () {
      expect(quarterly().overdueAmount(paid: 12000, asOf: day(8, 6)), 3000);
    });
  });

  group('where each line stands', () {
    test('oldest first, and only the past can be overdue', () {
      final lines = quarterly().standing(paid: 12000, asOf: day(8, 6));

      expect(lines[0].state, InstallmentState.paid);
      expect(lines[1].state, InstallmentState.overdue);
      expect(lines[1].settled, 2000);
      expect(lines[1].outstanding, 3000);
      expect(lines[2].state, InstallmentState.upcoming);
      expect(lines[3].state, InstallmentState.upcoming);
    });

    test('money on a future instalment is partial, never overdue', () {
      final lines = quarterly().standing(paid: 12000, asOf: day(7, 1));
      expect(lines[1].state, InstallmentState.partial);
    });

    test('days late are whole days from the due date', () {
      final lines = quarterly().standing(paid: 0, asOf: day(6, 8));
      expect(lines[0].daysLate, 7);
    });

    test('a plan typed out of order still reads in date order', () {
      final jumbled = BillingSchedule([
        Installment(label: 'October', dueDate: day(10, 5), amount: 5000),
        Installment(label: 'Upon enrolment', dueDate: day(6, 1), amount: 10000),
      ]);
      expect(jumbled.inDueOrder.first.label, 'Upon enrolment');
      // And the allocation follows it: 5,000 paid settles half the
      // enrolment payment, not the whole of October.
      final lines = jumbled.standing(paid: 5000, asOf: day(6, 2));
      expect(lines.first.installment.label, 'Upon enrolment');
      expect(lines.first.settled, 5000);
    });
  });

  group('what to chase next', () {
    test('the oldest overdue line, ahead of anything merely due', () {
      final next = quarterly().nextDue(paid: 0, asOf: day(8, 6));
      expect(next!.installment.label, 'Upon enrolment');
    });

    test('the next unpaid line when nothing is overdue', () {
      final next = quarterly().nextDue(paid: 10000, asOf: day(6, 2));
      expect(next!.installment.label, 'August');
    });

    test('nothing at all once the plan is settled', () {
      expect(quarterly().nextDue(paid: 25000, asOf: day(12, 31)), isNull);
    });
  });

  group('thirds, which do not divide', () {
    test('a centavo of drift does not leave a family owing forever', () {
      final schedule = BillingSchedule([
        Installment(label: 'One', dueDate: day(6, 1), amount: 3333.34),
        Installment(label: 'Two', dueDate: day(7, 1), amount: 3333.33),
        Installment(label: 'Three', dueDate: day(8, 1), amount: 3333.33),
      ]);
      expect(schedule.overdueAmount(paid: 10000, asOf: day(9, 1)), 0);
      expect(
        schedule.standing(paid: 10000, asOf: day(9, 1)).every((l) => l.state == InstallmentState.paid),
        isTrue,
      );
    });
  });

  group('a plan has to add up to the charge', () {
    FeeStructure structure(List<Installment> plan) => FeeStructure(
          id: 'fs1',
          name: 'Grade 10, SY 2026-2027',
          educationLevel: EducationLevel.highSchool,
          schoolYear: '2026-2027',
          items: const [
            FeeItem(label: 'Tuition', amount: 20000, category: FeeCategory.tuition),
            FeeItem(label: 'Miscellaneous', amount: 5000, category: FeeCategory.miscellaneous),
          ],
          installments: plan,
          updatedAt: DateTime(2026),
          updatedByName: 'Bursar',
        );

    test('no plan at all is fine -- the whole amount is due when charged', () {
      expect(structure(const []).scheduleBalances, isTrue);
    });

    test('a plan matching the fees is fine', () {
      expect(structure(quarterly().installments).scheduleBalances, isTrue);
    });

    test('a plan short of the fees is refused', () {
      // The one that tells a family they have finished paying when they
      // have not.
      final short = [...quarterly().installments]..removeLast();
      expect(structure(short).scheduleBalances, isFalse);
    });
  });

  group('every plan a student is under, as one', () {
    Assessment assessment({
      required String id,
      required double total,
      List<Installment> plan = const [],
      DateTime? voidedAt,
    }) =>
        Assessment(
          id: id,
          studentId: 'stu1',
          studentName: 'Bea Torres',
          schoolYear: '2026-2027',
          items: [FeeItem(label: 'Fees', amount: total)],
          installments: plan,
          assessedByName: 'Bursar',
          assessedAt: day(6, 1),
          voidedAt: voidedAt,
        );

    test('two assessments make one schedule', () {
      final combined = Assessment.combinedSchedule([
        assessment(id: 'a', total: 25000, plan: quarterly().installments),
        assessment(
          id: 'b',
          total: 800,
          plan: [Installment(label: 'Make-up exam', dueDate: day(11, 1), amount: 800)],
        ),
      ]);
      expect(combined.total, 25800);
      expect(combined.amountDueBy(day(11, 1)), 20800);
    });

    test('a charge with no plan falls due the day it was made', () {
      // Not excused from being overdue. A replacement ID charged in June
      // and unpaid in December is late, and leaving it out of the
      // schedule would quietly say otherwise.
      final combined = Assessment.combinedSchedule([assessment(id: 'a', total: 350)]);
      expect(combined.amountDueBy(day(6, 1)), 350);
      expect(combined.overdueAmount(paid: 0, asOf: day(12, 1)), 350);
    });

    test('a voided assessment chases nobody', () {
      final combined = Assessment.combinedSchedule([
        assessment(id: 'a', total: 25000, plan: quarterly().installments, voidedAt: day(7, 1)),
      ]);
      expect(combined.isEmpty, isTrue);
    });
  });
}
