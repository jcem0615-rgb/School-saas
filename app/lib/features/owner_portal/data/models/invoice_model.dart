import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/invoice.dart';

class InvoiceModel extends Invoice {
  const InvoiceModel({
    required super.id,
    required super.schoolId,
    required super.billingPeriodStart,
    required super.billingPeriodEnd,
    required super.dailyBreakdown,
    required super.totalAmount,
    required super.status,
    required super.dueDate,
    super.paidAt,
    super.paidAmount,
    super.paymentMethod,
    super.paymentReference,
  });

  factory InvoiceModel.fromFirestore(String id, Map<String, dynamic> data) {
    final rawBreakdown = data['dailyBreakdown'] as List<dynamic>? ?? [];
    return InvoiceModel(
      id: id,
      schoolId: data['schoolId'] as String,
      billingPeriodStart: (data['billingPeriodStart'] as Timestamp).toDate(),
      billingPeriodEnd: (data['billingPeriodEnd'] as Timestamp).toDate(),
      dailyBreakdown: rawBreakdown.map((raw) {
        final line = raw as Map<String, dynamic>;
        return DailyBillingLine(
          date: DateTime.parse(line['date'] as String),
          activeStudents: line['activeStudents'] as int,
          charge: (line['charge'] as num).toDouble(),
        );
      }).toList(),
      totalAmount: (data['totalAmount'] as num).toDouble(),
      status: InvoiceStatus.fromString(data['status'] as String),
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      paidAmount: (data['paidAmount'] as num?)?.toDouble(),
      paymentMethod: data['paymentMethod'] != null
          ? PaymentMethod.fromString(data['paymentMethod'] as String)
          : null,
      paymentReference: data['paymentReference'] as String?,
    );
  }
}
