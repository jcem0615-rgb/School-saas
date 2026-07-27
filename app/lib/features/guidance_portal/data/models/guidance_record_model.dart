import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/guidance_record.dart';

class GuidanceRecordModel extends GuidanceRecord {
  const GuidanceRecordModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.category,
    required super.notes,
    required super.recordedByName,
    required super.recordedAt,
  });

  factory GuidanceRecordModel.fromFirestore(String id, Map<String, dynamic> data) {
    return GuidanceRecordModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      category: GuidanceCategory.fromString(data['category'] as String? ?? 'other'),
      notes: data['notes'] as String? ?? '',
      recordedByName: data['recordedByName'] as String? ?? 'Unknown',
      recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
