import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/school_summary.dart';

class SchoolSummaryModel extends SchoolSummary {
  const SchoolSummaryModel({
    required super.id,
    required super.name,
    required super.status,
    required super.activeStudentCount,
    required super.currentCycleAccrued,
    super.logoUrl,
    super.gracePeriodStartedAt,
    super.suspendedAt,
  });

  /// Built by joining `platform_schools/{id}` (name/logo) with
  /// `platform_subscriptions/{id}` (status/billing) -- see
  /// OwnerRemoteDataSource.watchSchools for how the two streams are merged.
  factory SchoolSummaryModel.fromDocs({
    required String id,
    required Map<String, dynamic> schoolData,
    required Map<String, dynamic> subscriptionData,
  }) {
    return SchoolSummaryModel(
      id: id,
      name: schoolData['name'] as String? ?? 'Unnamed School',
      logoUrl: schoolData['logoUrl'] as String?,
      status: SchoolSubscriptionStatus.fromString(
        subscriptionData['currentStatus'] as String? ?? 'active',
      ),
      activeStudentCount: subscriptionData['activeStudentCountSnapshot'] as int? ?? 0,
      currentCycleAccrued: (subscriptionData['currentCycleAccrued'] as num?)?.toDouble() ?? 0.0,
      gracePeriodStartedAt:
          (subscriptionData['gracePeriodStartedAt'] as Timestamp?)?.toDate(),
      suspendedAt: (subscriptionData['suspendedAt'] as Timestamp?)?.toDate(),
    );
  }
}
