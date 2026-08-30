import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/domain/entities/approval_request.dart';
import 'package:logicclass/features/director_portal/presentation/screens/approvals_screen.dart';

/// A decided request has to say who decided it, when, and what they were
/// deciding. Before this it showed the remarks alone -- so weeks later
/// the one question anybody asks about an approval, "who approved this?",
/// had no answer on the screen that recorded it.
Future<ProviderContainer> _pump(WidgetTester tester, UserRole role) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(overrides: demoOverrides());
  addTearDown(c.dispose);
  final account = DemoStore.demoAccounts.firstWhere((a) => a.role == role);
  c.read(demoStoreProvider).acknowledgedPrivacy.add({account.uid});
  c.read(demoAuthRepositoryProvider).signInAs(account);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: ApprovalsScreen()),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('a decided request names who decided it and when',
      (tester) async {
    await _pump(tester, UserRole.director);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Approved'));
    await tester.pumpAndSettle();

    // The name and the role, not just the outcome.
    expect(find.textContaining('Approved by Elena Cruz (Director)'),
        findsOneWidget);
    // And the reason, which was the only part that used to show.
    expect(find.textContaining('Settle on or before the 30th'), findsOneWidget);
  });

  testWidgets('a declined request says who declined it', (tester) async {
    await _pump(tester, UserRole.director);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rejected'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Declined by Grace Mendoza (Admin)'),
        findsOneWidget);
    expect(find.textContaining('No medical certificate'), findsOneWidget);
  });

  testWidgets('the request details are on the card, not only its title',
      (tester) async {
    await _pump(tester, UserRole.director);

    // A pending material request: a director approving on the title alone
    // has no idea what quantity or cost they just agreed to.
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(find.text('Estimated cost'), findsWidgets);
    expect(find.text('850'), findsOneWidget);
  });

  testWidgets('deciding one records the account that decided it',
      (tester) async {
    final c = await _pump(tester, UserRole.director);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final decided = c
        .read(demoStoreProvider)
        .approvals
        .value
        .firstWhere((a) => a.id == 'apr_001');
    expect(decided.status, ApprovalStatus.approved);
    // The signed fields firestore.rules pins to the caller.
    expect(decided.decidedByUid, 'u_director');
    expect(decided.decidedByRole, 'director');
    expect(decided.decidedByName, 'Elena Cruz');
    expect(decided.decidedAt, isNotNull);
  });
}
