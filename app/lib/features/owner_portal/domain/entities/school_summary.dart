/// Status of a school's subscription, as seen from the Owner Portal.
/// Mirrors `platform_subscriptions.currentStatus` in Firestore.
enum SchoolSubscriptionStatus {
  active('active'),
  gracePeriod('grace_period'),
  suspended('suspended');

  final String value;
  const SchoolSubscriptionStatus(this.value);

  static SchoolSubscriptionStatus fromString(String value) =>
      SchoolSubscriptionStatus.values.firstWhere((s) => s.value == value);

  String get displayLabel => switch (this) {
        SchoolSubscriptionStatus.active => 'Active',
        SchoolSubscriptionStatus.gracePeriod => 'Grace Period',
        SchoolSubscriptionStatus.suspended => 'Suspended',
      };
}

/// A row in the Owner's school list -- deliberately lightweight (no full
/// address/contact block) since this is what renders in a scrollable list
/// of potentially hundreds of schools. Full detail is a separate entity
/// fetched only when the Owner drills into one school.
class SchoolSummary {
  final String id;
  final String name;
  final String? logoUrl;
  final SchoolSubscriptionStatus status;
  final int activeStudentCount;
  final double currentCycleAccrued; // PHP, running total this billing cycle
  final DateTime? gracePeriodStartedAt;
  final DateTime? suspendedAt;

  const SchoolSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.activeStudentCount,
    required this.currentCycleAccrued,
    this.logoUrl,
    this.gracePeriodStartedAt,
    this.suspendedAt,
  });
}
