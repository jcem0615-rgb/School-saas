import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/inventory/domain/entities/inventory_item.dart';
import 'package:logicclass/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:logicclass/features/inventory/presentation/screens/inventory_screen.dart';

/// What the stock room will accept.
///
/// The count on an item is a running total; the movements are the record
/// it has to be derivable from. Everything here is about keeping that
/// true — a figure nobody can trace back to a movement is the
/// spreadsheet this module replaces.
///
/// The concurrency guarantee is not here and cannot be: it lives in
/// `recordInventoryMovement` and is tested against a real Firestore in
/// `functions/test/shared/inventory-emulator/`.
void main() {
  Future<ProviderContainer> staffContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'staff@demo.ph'),
        );
    return container;
  }

  InventoryActionController actions(ProviderContainer container) {
    container.listen(inventoryActionControllerProvider, (_, __) {});
    return container.read(inventoryActionControllerProvider.notifier);
  }

  InventoryItem itemNamed(ProviderContainer container, String name) => container
      .read(demoStoreProvider)
      .inventory
      .value
      .firstWhere((i) => i.name == name);

  group('what a movement will accept', () {
    test('a quantity that is not a number is refused', () async {
      // `double.tryParse('NaN')` returns NaN for one word typed into the
      // quantity box, and `1e400` parses to Infinity. Every guard here
      // was a comparison, and `NaN <= 0` and `NaN == 0` are both false,
      // so both went straight through — into the running total, where
      // they are permanent: everything added to NaN stays NaN.
      final container = await staffContainer();
      addTearDown(container.dispose);
      final paper = itemNamed(container, 'Bond paper A4');

      for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
        final ok = await actions(container).recordMovement(
          item: paper,
          kind: MovementKind.received,
          quantity: bad,
        );
        expect(ok, isFalse, reason: '$bad');
      }
      expect(itemNamed(container, 'Bond paper A4').quantityOnHand, paper.quantityOnHand);
      expect(itemNamed(container, 'Bond paper A4').quantityOnHand.isFinite, isTrue);
    });

    test('a stock count may be a number that is not a number either', () async {
      // The adjustment path guards with `== 0` rather than `<= 0`, and
      // NaN fails that test just as cheerfully.
      final container = await staffContainer();
      addTearDown(container.dispose);

      final ok = await actions(container).recordMovement(
        item: itemNamed(container, 'Projector'),
        kind: MovementKind.adjusted,
        quantity: double.nan,
      );
      expect(ok, isFalse);
    });

    test('a movement of nothing is refused, and points at the stock count',
        () async {
      final container = await staffContainer();
      addTearDown(container.dispose);
      final paper = itemNamed(container, 'Bond paper A4');

      expect(
        await actions(container)
            .recordMovement(item: paper, kind: MovementKind.received, quantity: 0),
        isFalse,
      );
      expect(
        await actions(container)
            .recordMovement(item: paper, kind: MovementKind.adjusted, quantity: 0),
        isFalse,
      );
    });

    test('an issue with nobody on it is refused', () async {
      // "Where is the good projector" is the question this exists to
      // answer, and a movement out with nobody on it leaves the shrug.
      final container = await staffContainer();
      addTearDown(container.dispose);

      expect(
        await actions(container).recordMovement(
          item: itemNamed(container, 'Projector'),
          kind: MovementKind.issued,
          quantity: 1,
        ),
        isFalse,
      );
      expect(
        await actions(container).recordMovement(
          item: itemNamed(container, 'Projector'),
          kind: MovementKind.issued,
          quantity: 1,
          issuedTo: 'Room 204',
        ),
        isTrue,
      );
    });

    test('taking out more than there is is refused', () async {
      final container = await staffContainer();
      addTearDown(container.dispose);
      final projector = itemNamed(container, 'Projector');
      expect(projector.quantityOnHand, 2);

      expect(
        await actions(container).recordMovement(
          item: projector,
          kind: MovementKind.issued,
          quantity: 3,
          issuedTo: 'Room 204',
        ),
        isFalse,
      );
      expect(itemNamed(container, 'Projector').quantityOnHand, 2);
    });
  });

  group('the count and the log', () {
    test('move together, and the log still adds up to the count', () async {
      // The reconciliation. The running total is kept for the screens;
      // the movements are what it has to be derivable from.
      final container = await staffContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);

      await actions(container).recordMovement(
        item: itemNamed(container, 'Bond paper A4'),
        kind: MovementKind.received,
        quantity: 20,
        reference: 'DR-4471',
      );

      final paper = itemNamed(container, 'Bond paper A4');
      final itsMovements =
          store.inventoryMovements.value.where((m) => m.itemId == paper.id);
      expect(stockFromMovements(itsMovements), paper.quantityOnHand);
    });
  });

  group('the stock room screen', () {
    testWidgets('shows what is running out and who is holding what',
        (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await staffContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Named more than once on purpose: in the reorder card at the top,
      // in the list, and again wherever somebody is holding one.
      expect(find.text('Bond paper A4'), findsWidgets);
      expect(find.text('Out on issue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
