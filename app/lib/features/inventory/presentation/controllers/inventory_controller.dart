import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/inventory_remote_datasource.dart';
import '../../data/repositories_impl/inventory_repository_impl.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/usecases/inventory_usecases.dart';

final inventoryRemoteDataSourceProvider = Provider<InventoryRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('InventoryRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return InventoryRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingInventoryUser(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepositoryImpl(ref.watch(inventoryRemoteDataSourceProvider));
});

final inventoryItemsProvider = StreamProvider.autoDispose<List<InventoryItem>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchItems();
});

final inventoryMovementsProvider =
    StreamProvider.autoDispose.family<List<InventoryMovement>, String?>((ref, itemId) {
  return ref.watch(inventoryRepositoryProvider).watchMovements(itemId: itemId);
});

/// What needs reordering, emptiest first.
///
/// A provider rather than something a screen computes, because the
/// dashboard shows the count and the list shows the rows, and two places
/// deciding what "low" means is two places that can disagree.
final lowStockProvider = Provider.autoDispose<List<InventoryItem>>((ref) {
  return lowStock(
    ref.watch(inventoryItemsProvider).valueOrNull ?? const <InventoryItem>[],
  );
});

/// Who is holding what, from the movement log.
final outstandingIssuesProvider = Provider.autoDispose<Map<String, double>>((ref) {
  return outstandingIssues(
    ref.watch(inventoryMovementsProvider(null)).valueOrNull ??
        const <InventoryMovement>[],
  );
});

class InventoryActionController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _repository;

  InventoryActionController(this._repository) : super(const AsyncData(null));

  Future<bool> saveItem({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    String? location,
    String? note,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await SaveInventoryItemUseCase(_repository)(
      itemId: itemId,
      name: name,
      category: category,
      unit: unit,
      reorderLevel: reorderLevel,
      location: location,
      note: note,
    );
    return _finish(result);
  }

  Future<bool> recordMovement({
    required InventoryItem item,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await RecordMovementUseCase(_repository)(
      item: item,
      kind: kind,
      quantity: quantity,
      issuedTo: issuedTo,
      reference: reference,
      note: note,
    );
    return _finish(result);
  }

  Future<bool> deleteItem(String itemId) async {
    if (mounted) state = const AsyncLoading();
    return _finish(await _repository.deleteItem(itemId));
  }

  bool _finish(Result<Object?> result) {
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final inventoryActionControllerProvider =
    StateNotifierProvider.autoDispose<InventoryActionController, AsyncValue<void>>(
        (ref) {
  return InventoryActionController(ref.watch(inventoryRepositoryProvider));
});
