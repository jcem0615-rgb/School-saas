import '../../../../core/errors/result.dart';
import '../entities/inventory_item.dart';

abstract class InventoryRepository {
  Stream<List<InventoryItem>> watchItems();

  /// Every movement, newest first. Bounded by [limit] because the log
  /// only grows and the screens want the recent end of it.
  Stream<List<InventoryMovement>> watchMovements({String? itemId, int limit});

  Future<Result<String>> saveItem({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    String? location,
    String? note,
  });

  /// Records a movement and moves the running total with it, together.
  ///
  /// The two in one transaction is the whole point: a quantity that
  /// changed without a movement behind it is exactly the untraceable
  /// figure this module replaces.
  Future<Result<void>> recordMovement({
    required InventoryItem item,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  });

  Future<Result<void>> deleteItem(String itemId);
}
