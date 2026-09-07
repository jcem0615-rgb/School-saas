import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/inventory_item.dart';
import '../models/inventory_models.dart';

class ActingInventoryUser {
  final String uid;
  final String schoolId;
  final String name;
  const ActingInventoryUser({
    required this.uid,
    required this.schoolId,
    required this.name,
  });
}

class InventoryRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingInventoryUser _actingUser;

  const InventoryRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingInventoryUser actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  Stream<List<InventoryItemModel>> watchItems() => _firestore
      .collection(FirestorePaths.inventory(_actingUser.schoolId))
      .where('isDeleted', isEqualTo: false)
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryItemModel.fromFirestore(d.id, d.data()))
          .toList());

  /// How many movements a screen reads at once.
  ///
  /// Public because the reconciliation depends on knowing it: a total
  /// recomputed from a truncated log disagrees with the running total by
  /// exactly the movements that were cut off, and reporting that as
  /// drift would send somebody to count a shelf that is fine.
  static const movementPageSize = 100;

  Stream<List<InventoryMovementModel>> watchMovements({
    String? itemId,
    int limit = movementPageSize,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.inventoryTransactions(_actingUser.schoolId));
    if (itemId != null) query = query.where('itemId', isEqualTo: itemId);
    return query
        .orderBy('recordedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => InventoryMovementModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<String> saveItem({
    String? itemId,
    required Map<String, dynamic> fields,
  }) async {
    final collection =
        _firestore.collection(FirestorePaths.inventory(_actingUser.schoolId));
    final ref = itemId == null ? collection.doc() : collection.doc(itemId);
    await ref.set({
      ...fields,
      'id': ref.id,
      'schoolId': _actingUser.schoolId,
      // Only ever on create. An edit to a name must not silently reset
      // the count -- the movements are what change that.
      if (itemId == null) 'quantityOnHand': 0,
      if (itemId == null) 'isDeleted': false,
      if (itemId == null) 'createdBy': _actingUser.uid,
      if (itemId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Moves stock, on the server.
  ///
  /// This was a client transaction. It re-read the item -- the right
  /// instinct -- and then checked nothing against what it read: the
  /// below-zero test lived in the use case, against the copy of the item
  /// this screen was holding. Two people issuing the last two projectors
  /// at the same moment both passed it, and the shelf went to -2.
  ///
  /// `recordInventoryMovement` does the check inside the transaction
  /// against what is actually on file, and firestore.rules now refuses
  /// any client write to `quantityOnHand` -- so a count can only move by
  /// a movement, which is what makes the log the record it claims to be.
  Future<void> recordMovement({
    required String itemId,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  }) async {
    try {
      final callable = _functions.httpsCallable('recordInventoryMovement');
      await callable.call({
        'schoolId': _actingUser.schoolId,
        'itemId': itemId,
        'kind': kind.value,
        'quantity': quantity,
        'issuedTo': issuedTo,
        'reference': reference,
        'note': note,
      });
    } on FirebaseFunctionsException catch (e) {
      // The server's message rather than a generic one: it names how
      // many are actually on hand, which is the only thing the person
      // holding the clipboard can act on.
      throw ServerException(e.message ?? 'Could not record that movement.');
    }
  }

  /// Soft delete, like everything else here: firestore.rules denies a
  /// hard one, and an item with movements behind it should not vanish
  /// from the log's point of view.
  Future<void> deleteItem(String itemId) async {
    await _firestore
        .doc('${FirestorePaths.inventory(_actingUser.schoolId)}/$itemId')
        .update({
      'isDeleted': true,
      'deletedBy': _actingUser.uid,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
