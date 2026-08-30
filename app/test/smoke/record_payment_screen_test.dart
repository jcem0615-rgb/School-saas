import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/presentation/screens/record_payment_screen.dart';

/// The screen a cashier uses when they reach Record Payment without a
/// student already chosen.
///
/// It used to take any string as a student ID, hand back a receipt, and
/// move nobody's balance -- which is what "the student paid but the
/// balance is not deducting" looks like from the counter. It now has to
/// name the student before it will send anything.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(overrides: demoOverrides());
  addTearDown(c.dispose);
  final account =
      DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar);
  c.read(demoStoreProvider).acknowledgedPrivacy.add({account.uid});
  c.read(demoStoreProvider).acceptedTerms.add({account.uid});
  c.read(demoAuthRepositoryProvider).signInAs(account);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: RecordPaymentScreen()),
  ));
  await tester.pumpAndSettle();
  return c;
}

bool _recordEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Record Payment'),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('nothing is offered until an ID is entered', (tester) async {
    await _pump(tester);
    expect(
      find.text('Enter the student ID to see who this payment is for.'),
      findsOneWidget,
    );
    expect(_recordEnabled(tester), isFalse);
  });

  testWidgets('an ID that matches nobody is refused before it is sent',
      (tester) async {
    await _pump(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Student ID'), 'S-2026-000001');
    await tester.pumpAndSettle();

    expect(find.text('No student has that ID. Nothing will be recorded.'),
        findsOneWidget);
    // The refusal is the button, not an error afterwards: there is no
    // moment where a cashier believes the payment went through.
    expect(_recordEnabled(tester), isFalse);
  });

  testWidgets('the number printed on the ID card resolves the student',
      (tester) async {
    final c = await _pump(tester);
    final student = c.read(demoStoreProvider).students.value.first;

    await tester.enterText(
        find.widgetWithText(TextField, 'Student ID'), student.studentNumber);
    await tester.pumpAndSettle();

    // Name, number and class, so a cashier can check the record against
    // the person in front of them before taking any money.
    expect(find.text(student.fullName), findsOneWidget);
    expect(find.textContaining(student.studentNumber), findsWidgets);
    // And what they owe right now, which is the figure that proves the
    // deduction afterwards.
    expect(find.textContaining('Current balance:'), findsOneWidget);
    expect(_recordEnabled(tester), isTrue);
  });

  testWidgets('the record ID resolves the student too', (tester) async {
    final c = await _pump(tester);
    final student = c.read(demoStoreProvider).students.value.first;

    await tester.enterText(
        find.widgetWithText(TextField, 'Student ID'), student.id);
    await tester.pumpAndSettle();

    expect(find.text(student.fullName), findsOneWidget);
    expect(_recordEnabled(tester), isTrue);
  });
}
