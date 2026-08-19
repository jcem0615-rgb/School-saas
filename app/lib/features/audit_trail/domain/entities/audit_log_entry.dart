class AuditLogEntry {
  final String id;
  final String userId;
  final String userRole;
  final String userName;
  final String module;
  final String action;
  final String targetCollection;
  final String targetId;
  final Map<String, dynamic>? previousValue;
  final Map<String, dynamic>? newValue;
  final bool success;
  final String? remarks;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.userName,
    required this.module,
    required this.action,
    required this.targetCollection,
    required this.targetId,
    required this.success,
    required this.timestamp,
    this.previousValue,
    this.newValue,
    this.remarks,
  });
}
