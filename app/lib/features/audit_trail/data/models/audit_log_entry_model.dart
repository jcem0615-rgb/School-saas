import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/audit_log_entry.dart';

class AuditLogEntryModel extends AuditLogEntry {
  const AuditLogEntryModel({
    required super.id,
    required super.userId,
    required super.userRole,
    required super.userName,
    required super.module,
    required super.action,
    required super.targetCollection,
    required super.targetId,
    required super.success,
    required super.timestamp,
    super.previousValue,
    super.newValue,
    super.remarks,
  });

  factory AuditLogEntryModel.fromFirestore(String id, Map<String, dynamic> data) {
    return AuditLogEntryModel(
      id: id,
      userId: data['userId'] as String? ?? '',
      userRole: data['userRole'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Unknown',
      module: data['module'] as String? ?? '',
      action: data['action'] as String? ?? '',
      targetCollection: data['targetCollection'] as String? ?? '',
      targetId: data['targetId'] as String? ?? '',
      previousValue: (data['previousValue'] as Map<String, dynamic>?),
      newValue: (data['newValue'] as Map<String, dynamic>?),
      success: data['success'] as bool? ?? true,
      remarks: data['remarks'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
