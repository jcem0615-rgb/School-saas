import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/inventory_item.dart';

class InventoryItemModel extends InventoryItem {
  const InventoryItemModel({
    required super.id,
    required super.name,
    required super.category,
    required super.unit,
    required super.quantityOnHand,
    super.reorderLevel,
    super.location,
    super.note,
  });

  factory InventoryItemModel.fromFirestore(String id, Map<String, dynamic> data) =>
      InventoryItemModel(
        id: id,
        name: data['name'] as String? ?? '',
        category: data['category'] as String? ?? 'Uncategorised',
        unit: data['unit'] as String? ?? 'piece',
        quantityOnHand: (data['quantityOnHand'] as num?)?.toDouble() ?? 0,
        reorderLevel: (data['reorderLevel'] as num?)?.toDouble() ?? 0,
        location: data['location'] as String?,
        note: data['note'] as String?,
      );
}

class InventoryMovementModel extends InventoryMovement {
  const InventoryMovementModel({
    required super.id,
    required super.itemId,
    required super.itemName,
    required super.kind,
    required super.quantity,
    required super.recordedByName,
    required super.recordedAt,
    super.issuedTo,
    super.reference,
    super.note,
  });

  factory InventoryMovementModel.fromFirestore(String id, Map<String, dynamic> data) =>
      InventoryMovementModel(
        id: id,
        itemId: data['itemId'] as String? ?? '',
        itemName: data['itemName'] as String? ?? '',
        kind: MovementKind.fromString(data['kind'] as String? ?? ''),
        quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
        issuedTo: data['issuedTo'] as String?,
        reference: data['reference'] as String?,
        note: data['note'] as String?,
        recordedByName: data['recordedByName'] as String? ?? 'Unknown',
        recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
