/// What happened to a thing.
enum MovementKind {
  /// Arrived. A delivery, a donation, a purchase.
  received('received', 'Received', 1),

  /// Went out to somebody or somewhere, and is expected back or not.
  issued('issued', 'Issued', -1),

  /// Came back. A returned projector, an unused ream.
  returned('returned', 'Returned', 1),

  /// Counted, and the count disagreed with the books. The quantity is
  /// the difference, either way.
  adjusted('adjusted', 'Stock count', 0),

  /// Broken, lost, expired. Gone, and the log says why.
  writtenOff('written_off', 'Written off', -1);

  final String value;
  final String displayLabel;

  /// Which way this moves the count. Zero for an adjustment, whose
  /// quantity carries its own sign.
  final int direction;

  const MovementKind(this.value, this.displayLabel, this.direction);

  static MovementKind fromString(String value) => MovementKind.values
      .firstWhere((k) => k.value == value, orElse: () => MovementKind.adjusted);

  /// Whether this movement needs somebody's name against it.
  ///
  /// Issuing does: "where is the good projector" is the question this
  /// module exists to answer, and a movement out with nobody on it
  /// leaves the same shrug the logbook did.
  bool get needsRecipient => this == MovementKind.issued;
}

/// One movement of one item.
class InventoryMovement {
  final String id;
  final String itemId;
  final String itemName;
  final MovementKind kind;

  /// Always positive except for a downward stock count, which is the one
  /// place a negative is meaningful.
  final double quantity;

  /// Who or where it went to, for an issue. A person, or a room.
  final String? issuedTo;

  /// A delivery receipt, a purchase order, the approval request this
  /// answers. What ties this row to something outside the app.
  final String? reference;

  final String? note;
  final String recordedByName;
  final DateTime recordedAt;

  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.kind,
    required this.quantity,
    required this.recordedByName,
    required this.recordedAt,
    this.issuedTo,
    this.reference,
    this.note,
  });

  /// The signed effect on stock.
  double get effect =>
      kind == MovementKind.adjusted ? quantity : quantity * kind.direction;
}

/// Something the school owns or keeps a stock of.
class InventoryItem {
  final String id;
  final String name;

  /// "Office supplies", "Science equipment", "Textbooks". Free text, so
  /// a school's own words survive.
  final String category;

  /// What one of it is: ream, box, piece, set. Printed everywhere a
  /// quantity is, because "12" of an unstated thing is not information.
  final String unit;

  /// The running total, maintained alongside the movement that changed
  /// it. The movements are the record; this is the sum kept for the
  /// screens, and [stockFromMovements] is what checks it has not drifted.
  final double quantityOnHand;

  /// Tell somebody when stock falls to or below this. Zero means never.
  final double reorderLevel;

  /// Where it is kept. A stock room, a laboratory, a cabinet.
  final String? location;

  final String? note;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    this.reorderLevel = 0,
    this.location,
    this.note,
  });

  bool get isLow => reorderLevel > 0 && quantityOnHand <= reorderLevel;

  /// "12 reams", and "1 ream" rather than "1 reams".
  String get quantityLabel {
    final rounded = quantityOnHand == quantityOnHand.roundToDouble()
        ? quantityOnHand.toStringAsFixed(0)
        : quantityOnHand.toString();
    final plural = quantityOnHand == 1 ? unit : _pluralise(unit);
    return '$rounded $plural';
  }
}

/// Enough of a pluraliser for a unit label, and no more.
///
/// Not a general one, and not trying to be: the words it sees are the
/// stock units a school types -- ream, box, piece, set, litre, metre --
/// and the only cases worth handling are the sibilant endings that take
/// "es" and the -y that becomes -ies. A word already ending in "s" is
/// left alone, which covers "scissors" correctly and would get "bus"
/// wrong; nobody stocks buses by the ream.
String _pluralise(String unit) {
  final trimmed = unit.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.endsWith('s')) return trimmed;
  for (final ending in ['x', 'z', 'ch', 'sh']) {
    if (trimmed.endsWith(ending)) return '${trimmed}es';
  }
  if (trimmed.endsWith('y') && trimmed.length > 1) {
    return '${trimmed.substring(0, trimmed.length - 1)}ies';
  }
  return '${trimmed}s';
}

/// What the movements say the stock should be.
///
/// The reconciliation. `quantityOnHand` is a running total kept for the
/// screens; this recomputes it from the log, and the two disagreeing is
/// how a school finds out that something wrote a quantity without
/// writing a movement. That is worth being able to check: a stock figure
/// nobody can trace back is the spreadsheet this module replaces.
double stockFromMovements(Iterable<InventoryMovement> movements) {
  final total = movements.fold<double>(0, (sum, m) => sum + m.effect);
  return (total * 1000).roundToDouble() / 1000;
}

/// Everything at or below its reorder level, emptiest first.
///
/// Sorted by how far below rather than by name, because the thing that
/// ran out entirely matters more than the thing with two left, and a
/// list ordered alphabetically buries it.
List<InventoryItem> lowStock(Iterable<InventoryItem> items) {
  final low = items.where((i) => i.isLow).toList()
    ..sort((a, b) {
      final aShort = a.reorderLevel - a.quantityOnHand;
      final bShort = b.reorderLevel - b.quantityOnHand;
      return bShort.compareTo(aShort);
    });
  return low;
}

/// One person, one item, and how many of it they still hold.
class OutstandingIssue {
  final String holder;
  final String itemId;
  final String itemName;
  final double quantity;

  const OutstandingIssue({
    required this.holder,
    required this.itemId,
    required this.itemName,
    required this.quantity,
  });
}

/// What is out on issue, and to whom.
///
/// Netted per recipient per item, so somebody who took three chairs and
/// brought two back shows as holding one rather than as two rows that
/// have to be read together.
///
/// Keyed on the item's id rather than its name. Renaming "Projector" to
/// "Projector (Epson)" used to split whoever was holding one across two
/// rows that each looked like a different loan -- and a recipient whose
/// name happened to contain the separator collided with somebody else
/// entirely.
List<OutstandingIssue> outstandingIssues(Iterable<InventoryMovement> movements) {
  final quantities = <String, double>{};
  final holders = <String, String>{};
  final itemIds = <String, String>{};
  // The name as it stood at the most recent movement, tracked by time
  // rather than by arrival order -- the log is read newest-first today,
  // and a list whose labels depend on that would go stale the day
  // somebody sorts it the other way.
  final names = <String, ({String name, DateTime at})>{};

  for (final movement in movements) {
    final who = movement.issuedTo?.trim();
    if (who == null || who.isEmpty) continue;
    if (movement.kind != MovementKind.issued &&
        movement.kind != MovementKind.returned) {
      continue;
    }
    final key = '${movement.itemId}\u0000$who';
    quantities[key] = (quantities[key] ?? 0) +
        (movement.kind == MovementKind.issued ? movement.quantity : -movement.quantity);
    holders[key] = who;
    itemIds[key] = movement.itemId;
    final seen = names[key];
    if (seen == null || movement.recordedAt.isAfter(seen.at)) {
      names[key] = (name: movement.itemName, at: movement.recordedAt);
    }
  }

  // A recipient who has returned everything is not holding anything, and
  // a list that still names them is a list somebody has to mentally
  // filter every time they read it.
  final held = [
    for (final entry in quantities.entries)
      if (entry.value > 0)
        OutstandingIssue(
          holder: holders[entry.key]!,
          itemId: itemIds[entry.key]!,
          itemName: names[entry.key]!.name,
          quantity: entry.value,
        ),
  ];
  held.sort((a, b) {
    final byHolder = a.holder.compareTo(b.holder);
    return byHolder != 0 ? byHolder : a.itemName.compareTo(b.itemName);
  });
  return held;
}
