import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
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
  final ActingInventoryUser _actingUser;

  const InventoryRemoteDataSource({
    required FirebaseFirestore firestore,
    required ActingInventoryUser actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  Stream<List<InventoryItemModel>> watchItems() => _firestore
      .collection(FirestorePaths.inventory(_actingUser.schoolId))
      .where('isDeleted', isEqualTo: false)
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => InventoryItemModel.fromFirestore(d.id, d.data()))
          .toList());

  Stream<List<InventoryMovementModel>> watchMovements({String? itemId, int limit = 100}) {
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

  /// Writes the movement and moves the total in one transaction.
  ///
  /// Read the item inside the transaction rather than trusting the copy
  /// the screen is holding: two people issuing the last two projectors
  /// at once should not both succeed against a count they each read a
  /// moment before.
  Future<void> recordMovement({
    required String itemId,
    required String itemName,
    required MovementKind kind,
    required double quantity,
    String? issuedTo,
    String? reference,
    String? note,
  }) async {
    final itemRef =
        _firestore.doc('${FirestorePaths.inventory(_actingUser.schoolId)}/$itemId');
    final movementRef = _firestore
        .collection(FirestorePaths.inventoryTransactions(_actingUser.schoolId))
        .doc();

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) {
        throw StateError('That item is no longer on file.');
      }
      final onHand = (snap.data()?['quantityOnHand'] as num?)?.toDouble() ?? 0;
      final effect = kind == MovementKind.adjusted
          ? quantity
          : quantity * kind.direction;

      tx.set(movementRef, {
        'id': movementRef.id,
        'schoolId': _actingUser.schoolId,
        'itemId': itemId,
        'itemName': itemName,
        'kind': kind.value,
        'quantity': quantity,
        'issuedTo': issuedTo,
        'reference': reference,
        'note': note,
        'recordedBy': _actingUser.uid,
        'recordedByName': _actingUser.name,
        'recordedAt': FieldValue.serverTimestamp(),
        // What it moved from and to, so the log alone can be replayed
        // and checked without joining back to the item.
        'quantityBefore': onHand,
        'quantityAfter': onHand + effect,
      });

      tx.update(itemRef, {
        'quantityOnHand': onHand + effect,
        'updatedBy': _actingUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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
