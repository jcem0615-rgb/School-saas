/// Snapshot of cross-module numbers the Director cares about at a glance.
/// Computed on demand via Firestore aggregation queries (count/sum) rather
/// than a maintained rollup doc -- unlike the Owner's platform-wide
/// summary, a single school's daily numbers are cheap enough to query
/// live, and Directors expect same-second accuracy on attendance/payments.
class DirectorDashboardSummary {
  final int todayAttendancePresentCount;
  final int todayAttendanceTotalCount;
  final double todayPaymentsTotal;
  final int pendingApprovalsCount;
  final int upcomingMeetingsCount;

  const DirectorDashboardSummary({
    required this.todayAttendancePresentCount,
    required this.todayAttendanceTotalCount,
    required this.todayPaymentsTotal,
    required this.pendingApprovalsCount,
    required this.upcomingMeetingsCount,
  });

  double get todayAttendanceRate => todayAttendanceTotalCount == 0
      ? 0
      : todayAttendancePresentCount / todayAttendanceTotalCount;
}
