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
    String? to,
  }) =>
      InventoryMovement(
        id: 'mv_${kind.value}_$quantity',
        itemId: 'item_1',
        itemName: item,
        kind: kind,
        quantity: quantity,
        issuedTo: to,
        recordedByName: 'Ricardo Aquino',
        recordedAt: DateTime(2026, 6, 1),
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
    test('nets a return against the issue', () {
      // Somebody who took three and brought two back is holding one,
      // not two rows that have to be read together.
      final held = outstandingIssues([
        move(MovementKind.issued, 3, item: 'Chairs', to: 'Maria Santos'),
        move(MovementKind.returned, 2, item: 'Chairs', to: 'Maria Santos'),
      ]);
      expect(held['Maria Santos|Chairs'], 1);
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
      expect(held['Maria Santos|Projector'], 1);
      expect(held['Room 204|Projector'], 2);
    });

    test('ignores movements with nobody on them', () {
      // A delivery is not somebody holding something.
      expect(outstandingIssues([move(MovementKind.received, 20)]), isEmpty);
    });
  });

  group('saying it in words', () {
    test('a quantity carries its unit, and pluralises it', () {
      expect(item(onHand: 12, unit: 'ream').quantityLabel, '12 reams');
      expect(item(onHand: 1, unit: 'ream').quantityLabel, '1 ream');
      expect(item(onHand: 3, unit: 'box').quantityLabel, '3 boxes');
      expect(item(onHand: 2, unit: 'body').quantityLabel, '2 bodies');
    });

    test('a unit already plural is left alone', () {
      expect(item(onHand: 4, unit: 'scissors').quantityLabel, '4 scissors');
    });

    test('a fractional quantity keeps its fraction', () {
      expect(item(onHand: 2.5, unit: 'litre').quantityLabel, '2.5 litres');
    });
  });

  test('an issue is the movement that needs a name against it', () {
    // "Where is the good projector" is the question, and a movement out
    // with nobody on it leaves the same shrug the logbook did.
    expect(MovementKind.issued.needsRecipient, isTrue);
    expect(MovementKind.received.needsRecipient, isFalse);
    expect(MovementKind.writtenOff.needsRecipient, isFalse);
  });
}
