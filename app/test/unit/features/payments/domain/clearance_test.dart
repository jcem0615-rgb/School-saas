import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/director_portal/domain/entities/approval_request.dart';
import 'package:logicclass/features/payments/domain/entities/clearance.dart';
import 'package:logicclass/features/payments/domain/entities/installment.dart';
import 'package:logicclass/features/reports/domain/usecases/exam_permits_report.dart';

/// Who gets a permit.
///
/// Both directions are expensive. Turning away a student the school
/// already agreed to let sit is a scene in front of a classroom; letting
/// through somebody who owes six weeks of tuition is the reason the
/// permit exists at all.
void main() {
  DateTime day(int month, int d) => DateTime(2026, month, d);

  BillingSchedule plan() => BillingSchedule([
        Installment(label: 'Upon enrolment', dueDate: day(6, 1), amount: 10000),
        Installment(label: 'August', dueDate: day(8, 5), amount: 5000),
        Installment(label: 'October', dueDate: day(10, 5), amount: 5000),
      ]);

  PromissoryCover note({
    double amount = 5000,
    DateTime? settleBy,
    String reference = 'Payment deferral request',
  }) =>
      PromissoryCover(amount: amount, settleBy: settleBy, reference: reference);

  group('an account that is current', () {
    test('clears, and cites nothing', () {
      final clearance =
          clearanceFor(schedule: plan(), paid: 15000, asOf: day(8, 10));
      expect(clearance.outcome, ClearanceOutcome.cleared);
      expect(clearance.isCleared, isTrue);
      expect(clearance.note, isNull);
    });

    test('clears even with an unused note on file', () {
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 15000,
        asOf: day(8, 10),
        notes: [note()],
      );
      expect(clearance.outcome, ClearanceOutcome.cleared);
    });
  });

  group('an account that is behind', () {
    test('is blocked, and says by how much', () {
      final clearance =
          clearanceFor(schedule: plan(), paid: 10000, asOf: day(8, 10));
      expect(clearance.outcome, ClearanceOutcome.blocked);
      expect(clearance.overdue, 5000);
      expect(clearance.shortfall, 5000);
    });

    test('is cleared by a note that covers the whole of it', () {
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(8, 10),
        notes: [note(amount: 5000, settleBy: day(8, 30))],
      );
      expect(clearance.outcome, ClearanceOutcome.clearedByNote);
      expect(clearance.shortfall, 0);
      expect(clearance.note!.settleBy, day(8, 30));
    });

    test('is not cleared by a note that covers only part', () {
      // A note for 2,000 against 5,000 overdue leaves 3,000, and issuing
      // a permit on it would be the school agreeing to something nobody
      // agreed to.
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(8, 10),
        notes: [note(amount: 2000, settleBy: day(8, 30))],
      );
      expect(clearance.outcome, ClearanceOutcome.blocked);
      expect(clearance.shortfall, 3000);
      expect(clearance.note, isNotNull, reason: 'the partial note is still cited');
    });

    test('two notes together can cover it', () {
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(8, 10),
        notes: [
          note(amount: 2000, settleBy: day(8, 20)),
          note(amount: 3000, settleBy: day(9, 30)),
        ],
      );
      expect(clearance.outcome, ClearanceOutcome.clearedByNote);
      // The one about to run out is the one worth printing.
      expect(clearance.note!.settleBy, day(8, 20));
    });
  });

  group('a note that has run out', () {
    test('clears nobody the day after its date', () {
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(8, 31),
        notes: [note(amount: 5000, settleBy: day(8, 30))],
      );
      expect(clearance.outcome, ClearanceOutcome.blocked);
    });

    test('still clears on the date itself', () {
      // A note to settle by the 30th covers the exam on the 30th, which
      // is the whole point of asking for it.
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(8, 30),
        notes: [note(amount: 5000, settleBy: day(8, 30))],
      );
      expect(clearance.outcome, ClearanceOutcome.clearedByNote);
    });

    test('a note with no date covers indefinitely', () {
      // What every note written before the field existed means. Refusing
      // to honour it would turn away a student over a schema change.
      //
      // The note is for 10,000 rather than 5,000 because by Christmas the
      // whole plan has fallen due: a dated note is about *when* it stops
      // covering, not about how much it covers, and mixing the two up is
      // how a test ends up asserting the wrong thing.
      final clearance = clearanceFor(
        schedule: plan(),
        paid: 10000,
        asOf: day(12, 25),
        notes: [note(amount: 10000)],
      );
      expect(clearance.outcome, ClearanceOutcome.clearedByNote);
      expect(clearance.overdue, 10000);
    });
  });

  group('reading notes out of the approvals queue', () {
    ApprovalRequest approval({
      ApprovalStatus status = ApprovalStatus.approved,
      Map<String, dynamic>? details,
      String type = 'promissory_note',
    }) =>
        ApprovalRequest(
          id: 'apr1',
          type: type,
          title: 'Payment deferral request',
          details: details ??
              {'studentId': 'stu1', 'amount': 5000.0, 'settleBy': '2026-08-30T00:00:00.000'},
          requestedByName: 'Miguel Torres',
          requestedByRole: 'student',
          status: status,
          createdAt: day(8, 1),
        );

    test('an approved note becomes a cover', () {
      final covers = promissoryCoversByStudent([approval()]);
      expect(covers['stu1']!.single.amount, 5000);
      expect(covers['stu1']!.single.settleBy, day(8, 30));
    });

    test('a pending note covers nothing', () {
      // Clearing a student for having *asked* would make the approval
      // step decorative.
      expect(
        promissoryCoversByStudent([approval(status: ApprovalStatus.pending)]),
        isEmpty,
      );
    });

    test('a rejected note covers nothing', () {
      expect(
        promissoryCoversByStudent([approval(status: ApprovalStatus.rejected)]),
        isEmpty,
      );
    });

    test('another kind of approval is not a promissory note', () {
      expect(promissoryCoversByStudent([approval(type: 'leave_request')]), isEmpty);
    });

    test('a note naming no student is dropped rather than applied to all', () {
      expect(
        promissoryCoversByStudent([approval(details: {'amount': 5000.0})]),
        isEmpty,
      );
    });

    test('an unparseable date reads as open-ended, not as expired', () {
      final covers = promissoryCoversByStudent([
        approval(details: {
          'studentId': 'stu1',
          'amount': 5000.0,
          'settleBy': 'end of the month',
        }),
      ]);
      expect(covers['stu1']!.single.settleBy, isNull);
    });
  });
}
