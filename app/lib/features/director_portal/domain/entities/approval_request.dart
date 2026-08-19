enum ApprovalStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  final String value;
  const ApprovalStatus(this.value);

  static ApprovalStatus fromString(String value) =>
      ApprovalStatus.values.firstWhere((s) => s.value == value);
}

/// Generic approval-workflow entity. Concrete request types (purchase
/// request, leave request, material request, ...) are distinguished by
/// [type] and carry type-specific context in [details] rather than each
/// getting a bespoke collection -- this keeps the Director's single
/// "Approvals" inbox simple while downstream modules (Inventory, Staff
/// Portal, etc.) each just write into this same collection.
class ApprovalRequest {
  final String id;
  final String type;
  final String title;
  final String? description;
  final Map<String, dynamic> details;
  final String requestedByName;
  final String requestedByRole;
  final ApprovalStatus status;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionRemarks;
  final DateTime createdAt;

  const ApprovalRequest({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.requestedByName,
    required this.requestedByRole,
    required this.status,
    required this.createdAt,
    this.description,
    this.decidedByName,
    this.decidedAt,
    this.decisionRemarks,
  });
}
