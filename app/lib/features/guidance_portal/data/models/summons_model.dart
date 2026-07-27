import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/summons.dart';

class SummonsModel extends Summons {
  const SummonsModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.reason,
    required super.scheduledDate,
    required super.status,
    required super.issuedByName,
    required super.createdAt,
  });

  factory SummonsModel.fromFirestore(String id, Map<String, dynamic> data) {
    return SummonsModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      reason: data['reason'] as String? ?? '',
      scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: SummonsStatus.fromString(data['status'] as String? ?? 'pending'),
      issuedByName: data['issuedByName'] as String? ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
