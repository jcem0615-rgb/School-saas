import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/leave_request.dart';

class LeaveRequestModel {
  const LeaveRequestModel._();

  static LeaveRequest fromFirestore(String id, Map<String, dynamic> data) {
    return LeaveRequest(
      id: id,
      employeeUid: (data['employeeUid'] as String?) ?? '',
      employeeName: (data['employeeName'] as String?) ?? '',
      employeeRole: (data['employeeRole'] as String?) ?? '',
      type: LeaveType.fromString(data['type'] as String?),
      fromDate: (data['fromDate'] as String?) ?? '',
      toDate: (data['toDate'] as String?) ?? '',
      days: (data['days'] as num?)?.toInt() ?? 0,
      reason: (data['reason'] as String?) ?? '',
      status: LeaveStatus.fromString(data['status'] as String?),
      decidedByUid: data['decidedByUid'] as String?,
      decidedByName: data['decidedByName'] as String?,
      decidedByRole: data['decidedByRole'] as String?,
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
      decisionRemarks: data['decisionRemarks'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
