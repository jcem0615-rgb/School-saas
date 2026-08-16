import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/emergency_contact.dart';

class EmergencyContactModel extends EmergencyContact {
  const EmergencyContactModel({
    required super.id,
    required super.label,
    required super.phone,
    required super.sortOrder,
    required super.updatedAt,
    required super.updatedByName,
    super.notes,
  });

  factory EmergencyContactModel.fromFirestore(String id, Map<String, dynamic> data) {
    return EmergencyContactModel(
      id: id,
      label: data['label'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      notes: data['notes'] as String?,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedByName: data['updatedByName'] as String? ?? '',
    );
  }
}
