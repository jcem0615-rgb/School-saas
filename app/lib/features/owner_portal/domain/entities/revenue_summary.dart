/// Aggregate metrics shown at the top of the Owner Dashboard. Computed by
/// a Cloud Function (not read live from every school's data on the client)
/// since summing across potentially hundreds of tenants on-device would be
/// slow and Firestore-read-expensive. See functions/src/scheduled/dailyBillingJob.ts,
/// which maintains a rolling `platform_revenue_summary/current` doc.
class RevenueSummary {
  final double dailyRevenue;
  final double monthlyRevenue;
  final double yearlyRevenue;
  final int activeSchoolCount;
  final int totalActiveStudents;
  final int overdueSchoolCount;
  final int suspendedSchoolCount;
  final DateTime lastUpdated;

  const RevenueSummary({
    required this.dailyRevenue,
    required this.monthlyRevenue,
    required this.yearlyRevenue,
    required this.activeSchoolCount,
    required this.totalActiveStudents,
    required this.overdueSchoolCount,
    required this.suspendedSchoolCount,
    required this.lastUpdated,
  });
}
