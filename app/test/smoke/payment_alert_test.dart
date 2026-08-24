import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart'
    show paymentRepositoryProvider;
import 'package:logicclass/main.dart' as app;

/// The cashier is told when a family submits an online payment.
///
/// An online payment is only a claim until a registrar approves it --
/// nothing moves the student's balance in between. So the gap that matters
/// is between the family sending the money and the cashier noticing, and
/// that gap used to be "whenever somebody happens to open the Online
/// Payments screen".
void main() {
  Future<ProviderContainer> signedInAs(WidgetTester tester, UserRole? role) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    if (role != null) {
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == role),
          );
    }

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const app.LogicClassApp()));
    await tester.pumpAndSettle();
    return container;
  }

  /// Files a submission the way the online payment screen does.
  ///
  /// Deliberately not awaited: the demo repository simulates 600ms of
  /// network latency with a real Future.delayed, and awaiting that inside
  /// testWidgets' fake clock would block forever. The pump below is what
  /// actually advances past it.
  Future<void> familySubmits(
    WidgetTester tester,
    ProviderContainer container, {
    required String reference,
    double amount = 2500,
  }) async {
    unawaited(container.read(paymentRepositoryProvider).submitOnlinePayment(
          studentId: 'student-1',
          studentName: 'Miguel Torres',
          amount: amount,
          method: PaymentMethod.gcash,
          purpose: PaymentPurpose.tuition,
          referenceNumber: reference,
        ));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  }

  /// Dismisses whatever is on screen, so no SnackBar timer outlives the
  /// test and the next assertion starts from a clean slate.
  Future<void> dismissAlerts(WidgetTester tester) async {
    final messengerContext = tester.element(find.byType(Navigator).first);
    ScaffoldMessenger.of(messengerContext).clearSnackBars();
    await tester.pumpAndSettle();
  }

  testWidgets('a submission that lands while the cashier is signed in pops up',
      (tester) async {
    final container = await signedInAs(tester, UserRole.registrar);

    // The demo queue already holds a pending submission. It was there
    // before this session started, so it is a review queue, not news.
    expect(find.byType(SnackBar), findsNothing,
        reason: 'the backlog that already existed at sign-in is not announced');

    await familySubmits(tester, container, reference: 'GC-99001');

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Miguel Torres'), findsWidgets);
    expect(find.textContaining('GC-99001'), findsWidgets);
    expect(find.text('Review'), findsOneWidget);

    await dismissAlerts(tester);
  });

  testWidgets('an already-announced submission is not announced again',
      (tester) async {
    final container = await signedInAs(tester, UserRole.registrar);

    await familySubmits(tester, container, reference: 'GC-99002');
    expect(find.textContaining('GC-99002'), findsWidgets);
    await dismissAlerts(tester);

    // The next emission carries GC-99002 as well -- it is still pending --
    // but only the new one should be called out.
    await familySubmits(tester, container, reference: 'GC-99003');
    expect(find.textContaining('GC-99003'), findsWidgets);
    expect(find.textContaining('GC-99002'), findsNothing);

    await dismissAlerts(tester);
  });

  testWidgets('a role that does not review payments is not interrupted',
      (tester) async {
    final container = await signedInAs(tester, UserRole.faculty);

    await familySubmits(tester, container, reference: 'GC-99004');

    expect(find.byType(SnackBar), findsNothing,
        reason: 'faculty do not sit on the payment review queue');
  });

  testWidgets('the family who filed it is not the one alerted', (tester) async {
    // A submission can only be filed by somebody signed in -- the demo
    // store refuses one from a signed-out session, which is why there is
    // no "signed out" case here. The student files it; the cashier is the
    // one who needs telling, not them.
    final container = await signedInAs(tester, UserRole.student);

    await familySubmits(tester, container, reference: 'GC-99005');

    expect(find.byType(SnackBar), findsNothing,
        reason: 'the student filed it; they do not need announcing to');
  });

  testWidgets('a submission filed while another role was signed in still lands',
      (tester) async {
    // This is the path the demo role-switcher takes, and the path a shared
    // front-desk machine takes when one person signs out and the next signs
    // in. The submission arrives while nobody who reviews payments is
    // looking; the next cashier to look still needs telling.
    final container = await signedInAs(tester, UserRole.registrar);
    final auth = container.read(demoAuthRepositoryProvider);

    auth.signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student));
    await tester.pumpAndSettle();

    await familySubmits(tester, container, reference: 'GC-99006');
    expect(find.byType(SnackBar), findsNothing, reason: 'student is not a reviewer');

    auth.signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar));
    await tester.pumpAndSettle();

    expect(find.textContaining('GC-99006'), findsWidgets,
        reason: 'arrived while the cashier was away -- still news to them');

    await dismissAlerts(tester);
  });
}
