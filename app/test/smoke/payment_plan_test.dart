import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/entities/installment.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/presentation/widgets/payment_plan_card.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/reports/domain/usecases/overdue_report.dart';

/// What a family and a bursar are actually shown.
///
/// The arithmetic has its own tests; these are about the sentence a
/// person reads, because "you are overdue" put in front of somebody who
/// is not is the failure that costs a school a family.
void main() {
  DateTime day(int month, int d) => DateTime(2026, month, d);

  final plan = [
    Installment(label: 'Upon enrolment', dueDate: day(6, 1), amount: 10000),
    Installment(label: 'August', dueDate: day(8, 5), amount: 5000),
    Installment(label: 'October', dueDate: day(10, 5), amount: 5000),
  ];

  Assessment assessment({List<Installment> installments = const []}) => Assessment(
        id: 'asmt1',
        studentId: 'stu1',
        studentName: 'Bea Torres',
        schoolYear: '2026-2027',
        items: const [FeeItem(label: 'Tuition', amount: 20000)],
        installments: installments,
        assessedByName: 'Bursar',
        assessedAt: day(6, 1),
      );

  Payment payment(double amount) => Payment(
        id: 'pay1',
        studentId: 'stu1',
        amount: amount,
        method: PaymentMethod.cash,
        purpose: PaymentPurpose.tuition,
        receiptNumber: 'OR-1',
        collectedByName: 'Cashier',
        status: PaymentStatus.completed,
        createdAt: day(6, 1),
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Installment> installments,
    required double paid,
    required DateTime asOf,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PaymentPlanCard(
            assessments: [assessment(installments: installments)],
            payments: paid == 0 ? const [] : [payment(paid)],
            asOf: asOf,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a school with no plan is shown no card at all', (tester) async {
    // A school billing in one lump should never see an empty panel
    // asking to be filled in.
    await pumpCard(tester, installments: const [], paid: 0, asOf: day(9, 1));
    expect(find.text('Payment plan'), findsNothing);
  });

  testWidgets('says what is overdue and which payment it was', (tester) async {
    await pumpCard(tester, installments: plan, paid: 0, asOf: day(8, 10));

    expect(find.textContaining('overdue'), findsWidgets);
    expect(find.textContaining('Upon enrolment'), findsWidgets);
  });

  testWidgets('a family who paid ahead is told they are up to date', (tester) async {
    // The one that matters most. This family has paid 15,000 against a
    // 20,000 plan and owes nothing yet; a card that called them overdue
    // would be accusing somebody who is ahead.
    await pumpCard(tester, installments: plan, paid: 15000, asOf: day(8, 10));

    expect(find.textContaining('Up to date'), findsOneWidget);
    expect(find.textContaining('October'), findsWidgets);
  });

  testWidgets('a settled plan says so and asks for nothing', (tester) async {
    await pumpCard(tester, installments: plan, paid: 20000, asOf: day(12, 1));

    expect(find.textContaining('Fully paid'), findsOneWidget);
  });

  testWidgets('a paid instalment keeps its figure on screen', (tester) async {
    // Struck through rather than removed: a family checking what they
    // paid in June needs the number to still be there.
    await pumpCard(tester, installments: plan, paid: 10000, asOf: day(7, 1));

    expect(find.text('Paid · due 1 Jun 2026'), findsOneWidget);
  });

  group('the collections list', () {
    StudentSummary student(String id, String name) => StudentSummary(
          id: id,
          studentNumber: '2026-000$id',
          firstName: name.split(' ').first,
          lastName: name.split(' ').last,
          gradeLevel: 'Grade 10',
          section: 'Rizal',
          educationLevel: EducationLevel.highSchool,
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: day(6, 1),
        );

    test('leaves out a family who is merely mid-plan', () {
      final table = OverdueReport.build(
        students: [student('stu1', 'Bea Torres')],
        payments: [payment(10000)],
        assessments: [assessment(installments: plan)],
        asOf: day(7, 1),
      );
      expect(table.rows, isEmpty);
      expect(table.headline.first.caption, 'Nobody is behind');
    });

    test('names the oldest unpaid instalment, not the newest', () {
      final table = OverdueReport.build(
        students: [student('stu1', 'Bea Torres')],
        payments: const [],
        assessments: [assessment(installments: plan)],
        asOf: day(8, 10),
      );
      // Two lines are overdue; the row is about the one that has been
      // outstanding longest, because that is what makes a case old.
      expect(table.rows.first.cells[3], 'Upon enrolment');
      expect(table.rows.first.cells[6], '61-90 days');
    });

    test('warns that students without a plan cannot appear', () {
      // A collections list that looks complete and is not will be
      // trusted, and should not be.
      final table = OverdueReport.build(
        students: [student('stu1', 'Bea Torres'), student('stu2', 'Ana Cruz')],
        payments: const [],
        assessments: [assessment(installments: plan)],
        asOf: day(8, 10),
      );
      expect(table.note, contains('not on a payment plan'));
    });
  });
}
