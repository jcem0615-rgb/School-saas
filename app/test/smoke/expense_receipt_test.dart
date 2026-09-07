import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/domain/entities/expense.dart';
import 'package:logicclass/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:logicclass/features/director_portal/presentation/screens/expenses_screen.dart';

/// The receipt behind a spending row.
///
/// Two problems, and the second was the one that would have bitten
/// first.
///
/// `receiptUrl` existed on the entity, in the model, through the
/// repository and the data source and into the document — and no screen
/// ever set it. There was no way to attach a receipt to anything the
/// school spent, which for an expense ledger is the substantiation the
/// record exists for.
///
/// And the update path wrote the field unconditionally from a dialog
/// that did not carry it. So on the day something did populate it, the
/// first correction to a typo would have silently detached it. The demo
/// hid that: it fell back to `?? existing`, so the two implementations
/// disagreed and the demo was the one telling the nicer story.
void main() {
  Future<ProviderContainer> directorContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'director@demo.ph'),
        );
    return container;
  }

  DirectorActionController actions(ProviderContainer container) {
    container.listen(directorActionControllerProvider, (_, __) {});
    return container.read(directorActionControllerProvider.notifier);
  }

  Expense expenseById(ProviderContainer container, String id) =>
      container.read(demoStoreProvider).expenses.value.firstWhere((e) => e.id == id);

  const someReceipt = 'data:application/pdf;base64,JVBERi0xLjQK';

  group('attaching one', () {
    test('a new expense can carry its receipt', () async {
      final container = await directorContainer();
      addTearDown(container.dispose);

      final ok = await actions(container).createExpense(
        category: 'Supplies',
        description: 'Two boxes of chalk',
        amount: 480,
        date: DateTime(2026, 10, 4),
        receiptUrl: someReceipt,
        receiptFileName: 'chalk-or.pdf',
      );
      expect(ok, isTrue);

      final saved = container
          .read(demoStoreProvider)
          .expenses
          .value
          .firstWhere((e) => e.description == 'Two boxes of chalk');
      expect(saved.hasReceipt, isTrue);
      expect(saved.receiptFileName, 'chalk-or.pdf');
    });

    test('the seeded ledger shows both states, because a school has both',
        () async {
      final container = await directorContainer();
      addTearDown(container.dispose);
      final all = container.read(demoStoreProvider).expenses.value;

      expect(all.where((e) => e.hasReceipt), isNotEmpty);
      expect(all.where((e) => !e.hasReceipt), isNotEmpty);
    });
  });

  group('keeping one', () {
    test('an ordinary edit does not detach the receipt', () async {
      // The regression. Correcting a typo in the description must not
      // remove the document that substantiates the spending.
      final container = await directorContainer();
      addTearDown(container.dispose);
      final before = expenseById(container, 'exp_001');
      expect(before.hasReceipt, isTrue);

      await actions(container).updateExpense(
        expenseId: 'exp_001',
        category: before.category,
        description: 'Meralco - October billing (corrected)',
        amount: before.amount,
        date: before.date,
        receiptUrl: before.receiptUrl,
        receiptFileName: before.receiptFileName,
      );

      final after = expenseById(container, 'exp_001');
      expect(after.description, 'Meralco - October billing (corrected)');
      expect(after.receiptUrl, before.receiptUrl);
      expect(after.receiptFileName, before.receiptFileName);
    });

    test('and one can be removed on purpose', () async {
      // The other half of the same fix. `?? existing` in the demo made
      // this impossible while the real data source did it on every edit
      // by accident; now both write what the editor is showing.
      final container = await directorContainer();
      addTearDown(container.dispose);
      final before = expenseById(container, 'exp_001');

      await actions(container).updateExpense(
        expenseId: 'exp_001',
        category: before.category,
        description: before.description,
        amount: before.amount,
        date: before.date,
      );

      expect(expenseById(container, 'exp_001').hasReceipt, isFalse);
    });
  });

  group('what an amount may be', () {
    test('a number that is not a number is refused', () async {
      // `double.tryParse('NaN')` returns NaN, and `NaN <= 0` is false --
      // so the only guard on the amount waved it straight through into
      // the ledger, where every total that included the row read NaN.
      final container = await directorContainer();
      addTearDown(container.dispose);
      final countBefore = container.read(demoStoreProvider).expenses.value.length;

      for (final bad in [double.nan, double.infinity]) {
        expect(
          await actions(container).createExpense(
            category: 'Supplies',
            description: 'Something',
            amount: bad,
            date: DateTime(2026, 10, 4),
          ),
          isFalse,
          reason: '$bad',
        );
      }
      expect(container.read(demoStoreProvider).expenses.value, hasLength(countBefore));
      expect(
        container.read(demoStoreProvider).expenses.value
            .every((e) => e.amount.isFinite),
        isTrue,
      );
    });

    test('and an edit cannot smuggle one in either', () async {
      final container = await directorContainer();
      addTearDown(container.dispose);
      final before = expenseById(container, 'exp_002');

      expect(
        await actions(container).updateExpense(
          expenseId: 'exp_002',
          category: before.category,
          description: before.description,
          amount: double.nan,
          date: before.date,
        ),
        isFalse,
      );
      expect(expenseById(container, 'exp_002').amount, before.amount);
    });

    test('zero and negative are still refused, with their own message',
        () async {
      final container = await directorContainer();
      addTearDown(container.dispose);

      for (final bad in [0.0, -50.0]) {
        expect(
          await actions(container).createExpense(
            category: 'Supplies',
            description: 'Something',
            amount: bad,
            date: DateTime(2026, 10, 4),
          ),
          isFalse,
        );
      }
    });
  });

  group('the expenses screen', () {
    testWidgets('says which rows have a receipt and which do not',
        (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await directorContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ExpensesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // One seeded row carries a receipt; the other two say so plainly
      // rather than leaving a gap somebody has to interpret.
      expect(find.text('Receipt'), findsOneWidget);
      expect(find.text('No receipt'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
