import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/expense.dart';

class ExpenseModel extends Expense {
  const ExpenseModel({
    required super.id,
    required super.category,
    required super.description,
    required super.amount,
    required super.date,
    required super.recordedByName,
    super.receiptUrl,
  });

  factory ExpenseModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ExpenseModel(
      id: id,
      category: data['category'] as String? ?? '',
      description: data['description'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recordedByName: data['recordedByName'] as String? ?? 'Unknown',
      receiptUrl: data['receiptUrl'] as String?,
    );
  }
}
