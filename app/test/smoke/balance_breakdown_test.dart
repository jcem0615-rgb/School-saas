import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/presentation/widgets/balance_breakdown.dart';

/// The breakdown is the whole point of assessments: it turns a balance
/// from a number into an answer. What it must never do is imply the
/// assessments it lists are the whole story when they are not -- a school
/// partway through adopting this has balances that were typed in, and
/// showing only the assessments there would understate what is owed.

Assessment _assessment({
  required String id,
  required double amount,
  DateTime? voidedAt,
  String? sourceStructureName,
}) =>
    Assessment(
      id: id,
      studentId: 'stu_001',
      studentName: 'Miguel Torres',
      schoolYear: '2026-2027',
      sourceStructureName: sourceStructureName,
      items: [FeeItem(label: 'Tuition', amount: amount, category: FeeCategory.tuition)],
      assessedByName: 'Registrar',
      assessedAt: DateTime(2026, 6, 15),
      voidedAt: voidedAt,
    );

Payment _payment({
  required double amount,
  String? refundOf,
  PaymentStatus status = PaymentStatus.completed,
}) =>
    Payment(
      id: 'pay_$amount$refundOf',
      studentId: 'stu_001',
      amount: amount,
      method: PaymentMethod.cash,
      purpose: PaymentPurpose.tuition,
      status: status,
      receiptNumber: 'OR-0001',
      collectedByName: 'Registrar',
      createdAt: DateTime(2026, 7, 1),
      refundOf: refundOf,
    );

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  testWidgets('a balance that reconciles says nothing about a remainder', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 8500,
        assessments: [_assessment(id: 'a1', amount: 17000)],
        payments: [_payment(amount: 8500)],
      ),
    );

    expect(find.text('Total assessed'), findsOneWidget);
    expect(find.text('Less payments received'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(
      find.text('Not covered by an assessment'),
      findsNothing,
      reason: 'a stray warning on books that balance is worse than none',
    );
  });

  testWidgets('a hand-set balance is named, not hidden', (tester) async {
    await _pump(
      tester,
      const BalanceBreakdown(balance: 24000, assessments: [], payments: []),
    );

    expect(find.text('Not covered by an assessment'), findsOneWidget);
    expect(
      find.textContaining('set directly rather than assessed'),
      findsOneWidget,
      reason: 'the office needs to know which records still want an assessment',
    );
  });

  testWidgets('an overpayment reconciles without a warning', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: -500,
        assessments: [_assessment(id: 'a1', amount: 17000)],
        payments: [_payment(amount: 17500)],
      ),
    );

    // The books balance -- the credit is the balance itself, and the
    // header above this widget already says so.
    expect(find.text('Not covered by an assessment'), findsNothing);
  });

  testWidgets('a balance written down by hand is named too', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 10000,
        assessments: [_assessment(id: 'a1', amount: 17000)],
        payments: const [],
      ),
    );

    expect(find.text('Not covered by an assessment'), findsOneWidget);
    expect(find.textContaining('written off or corrected directly'), findsOneWidget);
  });

  // Floating point makes 17000 - 8500 - 8500 come out as 1.8e-12 often
  // enough that an unrounded comparison would warn about a centavo on a
  // balance that is exactly right.
  testWidgets('centavo arithmetic does not raise a false remainder', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 0.1 + 0.2,
        assessments: [_assessment(id: 'a1', amount: 0.3)],
        payments: const [],
      ),
    );

    expect(find.text('Not covered by an assessment'), findsNothing);
  });

  testWidgets('a refund row is not counted as money received', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 17000,
        assessments: [_assessment(id: 'a1', amount: 17000)],
        payments: [
          // The refunded original keeps its positive amount and is
          // marked refunded; the reversal is its own negative row. The
          // pair nets to zero, so 17000 charged and nothing net received
          // is exactly the 17000 balance.
          _payment(amount: 5000, status: PaymentStatus.refunded),
          _payment(amount: -5000, refundOf: 'pay_original'),
        ],
      ),
    );

    expect(find.text('Not covered by an assessment'), findsNothing);
  });

  testWidgets('a voided assessment is shown but charges nothing', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 0,
        assessments: [
          _assessment(
            id: 'a1',
            amount: 17000,
            sourceStructureName: 'Grade 10 - Full Year',
            voidedAt: DateTime(2026, 7, 2),
          ),
        ],
        payments: const [],
      ),
    );

    // Still on the record -- that is what makes the balance
    // reconstructable -- but contributing zero, so no remainder is
    // claimed either way.
    expect(find.textContaining('Grade 10 - Full Year'), findsOneWidget);
    expect(find.textContaining('Voided'), findsOneWidget);
    expect(find.text('Not covered by an assessment'), findsNothing);
  });

  testWidgets('assessment items are behind a tap, not stacked on the screen', (tester) async {
    await _pump(
      tester,
      BalanceBreakdown(
        balance: 17000,
        assessments: [
          _assessment(id: 'a1', amount: 17000, sourceStructureName: 'Grade 10 - Full Year'),
        ],
        payments: const [],
      ),
    );

    expect(find.text('Tuition  ·  Tuition'), findsNothing);
    await tester.tap(find.text('Grade 10 - Full Year'));
    await tester.pumpAndSettle();
    expect(find.text('Tuition  ·  Tuition'), findsOneWidget);
  });
}
