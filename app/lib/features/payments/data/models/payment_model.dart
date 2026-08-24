import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/payment.dart';

class PaymentModel extends Payment {
  const PaymentModel({
    required super.id,
    required super.studentId,
    required super.amount,
    required super.method,
    required super.receiptNumber,
    required super.collectedByName,
    required super.purpose,
    required super.status,
    required super.createdAt,
    super.referenceNumber,
    super.refundOf,
  });

  factory PaymentModel.fromFirestore(String id, Map<String, dynamic> data) {
    return PaymentModel(
      id: id,
      studentId: data['studentId'] as String,
      amount: (data['amount'] as num).toDouble(),
      method: PaymentMethod.fromString(data['method'] as String),
      referenceNumber: data['referenceNumber'] as String?,
      receiptNumber: data['receiptNumber'] as String? ?? '',
      collectedByName: data['collectedByName'] as String? ?? 'Unknown',
      purpose: PaymentPurpose.fromString(data['purpose'] as String? ?? 'other'),
      status: PaymentStatus.fromString(data['status'] as String? ?? 'completed'),
      refundOf: data['refundOf'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
