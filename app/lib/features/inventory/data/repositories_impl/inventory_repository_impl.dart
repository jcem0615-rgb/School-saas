import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_datasource.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDataSource _remote;
  const InventoryRepositoryImpl(this._remote);

  @override
  Stream<List<InventoryItem>> watchItems() => _remote.watchItems();

  @override
  Stream<List<InventoryMovement>> watchMovements({String? itemId, int limit = 100}) =>
      _remote.watchMovements(itemId: itemId, limit: limit);

  @override
  Future<Result<String>> saveItem({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    String? location,
    String? note,
  }) async {
    try {
      final id = await _remote.saveItem(itemId: itemId, fields: {
        'name': name,
        'category': category,
        'unit': unit,
        'reorderLevel': reorderLevel,
        'location': location,
        'note': note,
      });
      return Success(id);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> recordMovement({
    required InventoryItem item,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  }) async {
    try {
      await _remote.recordMovement(
        itemId: item.id,
        itemName: item.name,
        kind: kind,
        quantity: quantity,
        issuedTo: issuedTo,
        reference: reference,
        note: note,
      );
      return const Success(null);
    } on StateError catch (e) {
      return Error(ValidationFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> deleteItem(String itemId) async {
    try {
      await _remote.deleteItem(itemId);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
