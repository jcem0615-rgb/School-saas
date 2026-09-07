import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/inventory_item.dart';
import '../repositories/inventory_repository.dart';

class SaveInventoryItemUseCase {
  final InventoryRepository _repository;
  const SaveInventoryItemUseCase(this._repository);

  Future<Result<String>> call({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    String? location,
    String? note,
  }) {
    if (name.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('The item needs a name.')));
    }
    if (unit.trim().isEmpty) {
      // "12" of an unstated thing is not information, and every screen
      // that shows a quantity shows the unit beside it.
      return Future.value(const Error(ValidationFailure(
        'What is one of them? A ream, a box, a piece. A quantity with no '
        'unit is not something anybody can act on.',
      )));
    }
    if (reorderLevel < 0) {
      return Future.value(
        const Error(ValidationFailure('A reorder level cannot be negative.')),
      );
    }
    return _repository.saveItem(
      itemId: itemId,
      name: name.trim(),
      category: category.trim().isEmpty ? 'Uncategorised' : category.trim(),
      unit: unit.trim(),
      reorderLevel: reorderLevel,
      location: location?.trim(),
      note: note?.trim(),
    );
  }
}

class RecordMovementUseCase {
  final InventoryRepository _repository;
  const RecordMovementUseCase(this._repository);

  Future<Result<void>> call({
    required InventoryItem item,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  }) {
    // Checked before the comparisons, because the comparisons are what
    // let it through: `NaN <= 0` and `NaN == 0` are both false, so every
    // guard below waves it past -- and `double.tryParse('NaN')` returns
    // NaN, which is one word typed into the quantity box. A NaN reaching
    // the total is permanent: everything added to it stays NaN, and the
    // item reads "NaN reams" until somebody rebuilds the document by
    // hand. `1e400` parses to Infinity and is no better.
    if (!quantity.isFinite) {
      return Future.value(const Error(ValidationFailure(
        'A quantity has to be a number.',
      )));
    }

    if (kind == MovementKind.adjusted) {
      if (quantity == 0) {
        return Future.value(const Error(ValidationFailure(
          'A stock count that changes nothing is not worth recording.',
        )));
      }
    } else if (quantity <= 0) {
      return Future.value(const Error(ValidationFailure(
        'A movement has to be of something. Use a stock count to correct a '
        'figure downwards.',
      )));
    }

    if (kind.needsRecipient && (issuedTo == null || issuedTo.trim().isEmpty)) {
      // "Where is the good projector" is the question this module exists
      // to answer, and a movement out with nobody on it leaves the same
      // shrug the logbook did.
      return Future.value(const Error(ValidationFailure(
        'Who or where is it going to? A person, or a room.',
      )));
    }

    // Going below zero is refused rather than allowed and flagged. A
    // negative stock figure is always wrong -- either the movement is a
    // mistake or the shelf was already wrong, and both want somebody to
    // stop and count rather than a number that cannot be true.
    //
    // This check is a courtesy and not the guarantee. It runs against
    // [item], which is whatever the screen last received, and two people
    // reaching for the last projector at once both pass it. The one that
    // holds is inside `recordInventoryMovement`, against what is on file
    // at the moment of the write. What this buys is a message before the
    // round trip rather than after it.
    final effect = kind == MovementKind.adjusted ? quantity : quantity * kind.direction;
    if (item.quantityOnHand + effect < 0) {
      return Future.value(Error(ValidationFailure(
        'There are only ${item.quantityLabel} on hand. Record a stock count '
        'first if the shelf disagrees with the books.',
      )));
    }

    return _repository.recordMovement(
      item: item,
      kind: kind,
      quantity: quantity,
      issuedTo: issuedTo?.trim(),
      reference: reference?.trim(),
      note: note?.trim(),
    );
  }
}
