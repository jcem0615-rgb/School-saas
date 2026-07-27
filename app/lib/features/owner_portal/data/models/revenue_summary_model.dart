import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/revenue_summary.dart';

class RevenueSummaryModel extends RevenueSummary {
  const RevenueSummaryModel({
    required super.dailyRevenue,
    required super.monthlyRevenue,
    required super.yearlyRevenue,
    required super.activeSchoolCount,
    required super.totalActiveStudents,
    required super.overdueSchoolCount,
    required super.suspendedSchoolCount,
    required super.lastUpdated,
  });

  factory RevenueSummaryModel.fromFirestore(Map<String, dynamic> data) {
    return RevenueSummaryModel(
      dailyRevenue: (data['dailyRevenue'] as num?)?.toDouble() ?? 0.0,
      monthlyRevenue: (data['monthlyRevenue'] as num?)?.toDouble() ?? 0.0,
      yearlyRevenue: (data['yearlyRevenue'] as num?)?.toDouble() ?? 0.0,
      activeSchoolCount: data['activeSchoolCount'] as int? ?? 0,
      totalActiveStudents: data['totalActiveStudents'] as int? ?? 0,
      overdueSchoolCount: data['overdueSchoolCount'] as int? ?? 0,
      suspendedSchoolCount: data['suspendedSchoolCount'] as int? ?? 0,
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
