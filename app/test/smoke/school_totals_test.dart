import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/school_totals/presentation/controllers/school_totals_controller.dart';
import 'package:logicclass/features/school_totals/presentation/widgets/school_totals_card.dart';

/// The numbers the Owner has always had, now on the dashboard of the
/// people who run the school -- and the money half withheld from the one
/// role that is deliberately not allowed it.
Future<ProviderContainer> _pump(WidgetTester tester, UserRole role) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(overrides: demoOverrides());
  addTearDown(c.dispose);
  final account = DemoStore.demoAccounts.firstWhere((a) => a.role == role);
  c.read(demoStoreProvider).acknowledgedPrivacy.add({account.uid});
  c.read(demoStoreProvider).acceptedTerms.add({account.uid});
  c.read(demoAuthRepositoryProvider).signInAs(account);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SchoolTotalsCard())),
    ),
  ));
  // Pumped by hand rather than with pumpAndSettle. The card shows a
  // CircularProgressIndicator while the figures are in flight, and that
  // animation never stops scheduling frames -- pumpAndSettle waits for it
  // until its own timeout and then fails, which is a hang, not a result.
  //
  // Pumping is also the only thing that advances the clock in here. A
  // bare `await Future.delayed(...)` in a widget test waits on the fake
  // clock nothing is winding, and hangs until the runner is killed --
  // which is exactly how this test first failed.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  return c;
}

void main() {
  testWidgets('the count is the enrolled students, not every record',
      (tester) async {
    final c = await _pump(tester, UserRole.registrar);
    final students = c.read(demoStoreProvider).students.value;
    final enrolled =
        students.where((s) => s.status == StudentStatus.enrolled).length;

    // The seeds carry at least one student who is not enrolled, or this
    // test proves nothing.
    expect(enrolled, lessThan(students.length));
    expect(find.text('$enrolled'), findsOneWidget);
    expect(find.text('Active students'), findsOneWidget);
  });

  testWidgets('outstanding counts what is owed, never a credit balance',
      (tester) async {
    final c = await _pump(tester, UserRole.director);
    final students = c.read(demoStoreProvider).students.value;
    final owing = students.where((s) => s.balance > 0).toList();

    expect(find.textContaining('Outstanding'), findsOneWidget);
    expect(
      find.textContaining('${owing.length} students'),
      findsOneWidget,
      reason: 'the number of families owing is the figure a registrar acts on',
    );

    // A credit balance is money the school holds. Netting it against
    // arrears would let one family's overpayment cancel another's debt.
    final totals = await c.read(schoolTotalsProvider.future);
    final positiveOnly = owing.fold<double>(0, (sum, s) => sum + s.balance);
    expect(totals.outstanding, positiveOnly);
    expect(totals.outstanding, greaterThanOrEqualTo(0));
  });

  testWidgets('a principal sees the head count and no money', (tester) async {
    await _pump(tester, UserRole.principal);

    expect(find.text('Active students'), findsOneWidget);
    // Not an omission to wonder about: academic oversight and the
    // school's money are separate, and the card says which.
    expect(find.textContaining('Outstanding'), findsNothing);
    expect(find.textContaining('Collected this month'), findsNothing);
    expect(
      find.textContaining('sit with the Director, Admin and Registrar'),
      findsOneWidget,
    );
  });

  test('the money half is offered to the three roles that collect it',
      () async {
    // A plain test, not a widget one. This is repository behaviour rather
    // than layout, and three containers in one widget test leave the
    // demo's latency timers pending when the test body ends -- which
    // fails on !timersPending rather than on anything about the feature.
    for (final role in [UserRole.director, UserRole.admin, UserRole.registrar]) {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      c.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == role),
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final totals = await c.read(schoolTotalsProvider.future);
      expect(totals.includesMoney, isTrue,
          reason: '${role.value} is a role that collects money');
      expect(totals.collectedThisMonth, isNotNull);
      expect(totals.activeStudents, greaterThan(0));
    }
  });

  test('a principal is refused the money at the repository, not the widget',
      () async {
    // The card hiding it would be a UI decision. This is the boundary
    // itself: the repository does not hand a Principal a balance to
    // render in the first place.
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.principal),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final totals = await c.read(schoolTotalsProvider.future);
    expect(totals.includesMoney, isFalse);
    expect(totals.outstanding, isNull);
    expect(totals.collectedThisMonth, isNull);
    expect(totals.activeStudents, greaterThan(0));
  });
}
