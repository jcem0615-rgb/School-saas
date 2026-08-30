import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/approval_request.dart';

class ApprovalRequestModel extends ApprovalRequest {
  const ApprovalRequestModel({
    required super.id,
    required super.type,
    required super.title,
    required super.details,
    required super.requestedByName,
    required super.requestedByRole,
    required super.status,
    required super.createdAt,
    super.description,
    super.decidedByUid,
    super.decidedByName,
    super.decidedByRole,
    super.decidedAt,
    super.decisionRemarks,
  });

  factory ApprovalRequestModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ApprovalRequestModel(
      id: id,
      type: data['type'] as String? ?? 'other',
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      details: (data['details'] as Map<String, dynamic>?) ?? {},
      requestedByName: data['requestedByName'] as String? ?? 'Unknown',
      requestedByRole: data['requestedByRole'] as String? ?? 'unknown',
      status: ApprovalStatus.fromString(data['status'] as String? ?? 'pending'),
      decidedByUid: data['decidedByUid'] as String?,
      decidedByName: data['decidedByName'] as String?,
      decidedByRole: data['decidedByRole'] as String?,
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
      decisionRemarks: data['decisionRemarks'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
