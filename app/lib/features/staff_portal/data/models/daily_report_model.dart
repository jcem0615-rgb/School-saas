import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/daily_report.dart';

class DailyReportModel extends DailyReport {
  const DailyReportModel({
    required super.id,
    required super.date,
    required super.content,
    required super.staffName,
    required super.submittedAt,
  });

  factory DailyReportModel.fromFirestore(String id, Map<String, dynamic> data) {
    return DailyReportModel(
      id: id,
      date: data['date'] as String? ?? '',
      content: data['content'] as String? ?? '',
      staffName: data['staffName'] as String? ?? 'Unknown',
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
