import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/inventory/domain/entities/inventory_item.dart';

/// The stock room.
///
/// The question this module exists to answer is "where is the good
/// projector", and the failure it exists to prevent is a quantity nobody
/// can trace back to a movement. Most of these test that second thing.
void main() {
  InventoryMovement move(
    MovementKind kind,
    double quantity, {
    String item = 'Projector',
    String? itemId,
    String? to,
    DateTime? at,
  }) =>
      InventoryMovement(
        id: 'mv_${kind.value}_${quantity}_${to ?? ''}_$item',
        // Defaults to the name so two differently-named items in one
        // test are two items, and can be made to disagree deliberately
        // when the point is a rename.
        itemId: itemId ?? item,
        itemName: item,
        kind: kind,
        quantity: quantity,
        issuedTo: to,
        recordedByName: 'Ricardo Aquino',
        recordedAt: at ?? DateTime(2026, 6, 1),
      );

  InventoryItem item({
    String name = 'Bond paper',
    double onHand = 12,
    double reorder = 0,
    String unit = 'ream',
  }) =>
      InventoryItem(
        id: 'item_1',
        name: name,
        category: 'Office supplies',
        unit: unit,
        quantityOnHand: onHand,
        reorderLevel: reorder,
      );

  group('what the movements add up to', () {
    test('receiving adds and issuing takes away', () {
      expect(
        stockFromMovements([
          move(MovementKind.received, 20),
          move(MovementKind.issued, 5),
        ]),
        15,
      );
    });

    test('a return puts it back', () {
      expect(
        stockFromMovements([
          move(MovementKind.received, 10),
          move(MovementKind.issued, 4),
          move(MovementKind.returned, 3),
        ]),
        9,
      );
    });

    test('a write-off takes it out and leaves the reason behind', () {
      expect(
        stockFromMovements([
          move(MovementKind.received, 10),
          move(MovementKind.writtenOff, 2),
        ]),
        8,
      );
    });

    test('a stock count carries its own sign, either way', () {
      // The one movement where a negative is meaningful: the shelf had
      // fewer than the books said, or more.
      expect(
        stockFromMovements([
          move(MovementKind.received, 10),
          move(MovementKind.adjusted, -3),
        ]),
        7,
      );
      expect(
        stockFromMovements([
          move(MovementKind.received, 10),
          move(MovementKind.adjusted, 2),
        ]),
        12,
      );
    });

    test('nothing recorded is nothing on hand, not an error', () {
      expect(stockFromMovements(const []), 0);
    });

    test('fractional units do not accumulate a rounding tail', () {
      // Litres of reagent, metres of cable. Three tenths taken three
      // times should leave nine tenths, not 0.8999999999999999.
      final total = stockFromMovements([
        move(MovementKind.received, 1.2),
        move(MovementKind.issued, 0.1),
        move(MovementKind.issued, 0.1),
        move(MovementKind.issued, 0.1),
      ]);
      expect(total, 0.9);
    });
  });

  group('what needs reordering', () {
    test('is what has fallen to or below its level', () {
      final low = lowStock([
        item(name: 'Bond paper', onHand: 3, reorder: 5),
        item(name: 'Chalk', onHand: 5, reorder: 5),
        item(name: 'Markers', onHand: 40, reorder: 5),
      ]);
      expect(low.map((i) => i.name), ['Bond paper', 'Chalk']);
    });

    test('leaves out anything with no level set', () {
      // Zero means the school does not track a level for it, not that
      // it needs reordering the moment it is empty.
      expect(lowStock([item(onHand: 0, reorder: 0)]), isEmpty);
    });

    test('puts what ran out entirely above what is merely low', () {
      // A list ordered alphabetically buries the empty shelf.
      final low = lowStock([
        item(name: 'Chalk', onHand: 4, reorder: 5),
        item(name: 'Bond paper', onHand: 0, reorder: 10),
      ]);
      expect(low.first.name, 'Bond paper');
    });
  });

  group('who is holding what', () {
    double heldBy(List<OutstandingIssue> issues, String who, String what) => issues
        .where((i) => i.holder == who && i.itemName == what)
        .fold<double>(0, (sum, i) => sum + i.quantity);

    test('nets a return against the issue', () {
      // Somebody who took three and brought two back is holding one,
      // not two rows that have to be read together.
      final held = outstandingIssues([
        move(MovementKind.issued, 3, item: 'Chairs', to: 'Maria Santos'),
        move(MovementKind.returned, 2, item: 'Chairs', to: 'Maria Santos'),
      ]);
      expect(held, hasLength(1));
      expect(held.single.quantity, 1);
      expect(held.single.holder, 'Maria Santos');
      expect(held.single.itemName, 'Chairs');
    });

    test('drops anybody who has returned everything', () {
      final held = outstandingIssues([
        move(MovementKind.issued, 1, to: 'Maria Santos'),
        move(MovementKind.returned, 1, to: 'Maria Santos'),
      ]);
      expect(held, isEmpty);
    });

    test('keeps two people holding the same thing apart', () {
      final held = outstandingIssues([
        move(MovementKind.issued, 1, to: 'Maria Santos'),
        move(MovementKind.issued, 2, to: 'Room 204'),
      ]);
      expect(heldBy(held, 'Maria Santos', 'Projector'), 1);
      expect(heldBy(held, 'Room 204', 'Projector'), 2);
    });

    test('ignores movements with nobody on them', () {
      // A delivery is not somebody holding something.
      expect(outstandingIssues([move(MovementKind.received, 20)]), isEmpty);
    });

    test('a renamed item stays one loan rather than becoming two', () {
      // Keyed on the item's id. On the name, renaming "Projector" to
      // "Projector (Epson)" split whoever was holding one across two
      // rows that each looked like a different loan -- and the return
      // never cancelled the issue.
      final held = outstandingIssues([
        move(MovementKind.issued, 2,
            item: 'Projector', itemId: 'item_1', to: 'Maria Santos',
            at: DateTime(2026, 6, 1)),
        move(MovementKind.returned, 1,
            item: 'Projector (Epson)', itemId: 'item_1', to: 'Maria Santos',
            at: DateTime(2026, 6, 8)),
      ]);
      expect(held, hasLength(1));
      expect(held.single.quantity, 1);
      // Labelled with the name it was last moved under, not the one it
      // had when the loan started. Nobody in the stock room calls it the
      // old thing any more.
      expect(held.single.itemName, 'Projector (Epson)');
    });

    test('two items whose names collide in a key are still two items', () {
      // The old key was '$who|$itemName', so a recipient or an item name
      // containing the separator could be read as somebody else's row.
      final held = outstandingIssues([
        move(MovementKind.issued, 1,
            item: 'Chalk', itemId: 'item_a', to: 'Maria|Santos'),
        move(MovementKind.issued, 1,
            item: 'Santos|Chalk', itemId: 'item_b', to: 'Maria'),
      ]);
      expect(held, hasLength(2));
    });

    test('is ordered by who is holding it', () {
      final held = outstandingIssues([
        move(MovementKind.issued, 1, item: 'Chalk', to: 'Room 204'),
        move(MovementKind.issued, 1, item: 'Chairs', to: 'Ana Cruz'),
      ]);
      expect(held.map((i) => i.holder), ['Ana Cruz', 'Room 204']);
    });
  });
}
