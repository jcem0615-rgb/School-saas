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
