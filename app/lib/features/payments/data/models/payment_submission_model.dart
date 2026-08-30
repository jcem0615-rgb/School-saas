import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/payment.dart';
import '../../domain/entities/payment_submission.dart';

class PaymentSubmissionModel extends PaymentSubmission {
  const PaymentSubmissionModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.submittedByName,
    required super.submittedByRole,
    required super.amount,
    required super.method,
    required super.purpose,
    required super.referenceNumber,
    required super.status,
    required super.submittedAt,
    super.destinationLabel,
    super.receiptUrl,
    super.receiptFileName,
    super.reviewedByName,
    super.reviewedAt,
    super.decisionRemarks,
    super.resultingPaymentId,
  });

  factory PaymentSubmissionModel.fromFirestore(String id, Map<String, dynamic> data) {
    return PaymentSubmissionModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      submittedByName: data['submittedByName'] as String? ?? 'Unknown',
      submittedByRole: data['submittedByRole'] as String? ?? 'student',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      method: PaymentMethod.fromString(data['method'] as String? ?? 'gcash'),
      purpose: PaymentPurpose.fromString(data['purpose'] as String? ?? 'tuition'),
      referenceNumber: data['referenceNumber'] as String? ?? '',
      destinationLabel: data['destinationLabel'] as String?,
      receiptUrl: data['receiptUrl'] as String?,
      receiptFileName: data['receiptFileName'] as String?,
      status: SubmissionStatus.fromString(data['status'] as String? ?? 'pending'),
      reviewedByName: data['reviewedByName'] as String?,
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      decisionRemarks: data['decisionRemarks'] as String?,
      resultingPaymentId: data['resultingPaymentId'] as String?,
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
