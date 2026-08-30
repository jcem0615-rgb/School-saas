/// Why somebody is away.
///
/// Named kinds rather than free text, because payroll treats them
/// differently -- unpaid leave is a deduction, sick leave against an
/// entitlement, and "away" with no kind is a row nobody can act on.
enum LeaveType {
  sick('sick', 'Sick leave'),
  vacation('vacation', 'Vacation leave'),
  emergency('emergency', 'Emergency leave'),
  bereavement('bereavement', 'Bereavement leave'),
  maternity('maternity', 'Maternity or paternity leave'),
  unpaid('unpaid', 'Leave without pay');

  final String value;
  final String displayLabel;
  const LeaveType(this.value, this.displayLabel);

  static LeaveType fromString(String? value) => LeaveType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => LeaveType.unpaid,
      );

  /// Whether the day is still paid. Drives nothing automatically -- this
  /// system does not cut payslips -- but it is the distinction a payroll
  /// clerk is reading the timesheet to find, so it is named here rather
  /// than left for them to remember.
  bool get isPaid => this != LeaveType.unpaid;
}

enum LeaveStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Cancelled');

  final String value;
  final String displayLabel;
  const LeaveStatus(this.value, this.displayLabel);

  static LeaveStatus fromString(String? value) => LeaveStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => LeaveStatus.pending,
      );

  bool get isDecided => this == approved || this == declined;
}

/// One request to be away, and what became of it.
///
/// Dates are 'YYYY-MM-DD' strings rather than timestamps, deliberately.
/// Leave is counted in days, not moments: "the 3rd to the 5th" means
/// three whole days wherever the person filing it happens to be, and a
/// timestamp would make that answer depend on a timezone. The same
/// reasoning the attendance date key already follows.
class LeaveRequest {
  final String id;
  final String employeeUid;
  final String employeeName;
  final String employeeRole;
  final LeaveType type;

  /// Inclusive, both ends.
  final String fromDate;
  final String toDate;

  /// Working days covered, weekends excluded. Stored rather than
  /// recomputed on read so a request keeps the count it was filed and
  /// approved on, even if the school later changes what a working week
  /// means.
  final int days;

  final String reason;
  final LeaveStatus status;

  final String? decidedByUid;
  final String? decidedByName;
  final String? decidedByRole;
  final DateTime? decidedAt;
  final String? decisionRemarks;
  final DateTime createdAt;

  const LeaveRequest({
    required this.id,
    required this.employeeUid,
    required this.employeeName,
    required this.employeeRole,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.decidedByUid,
    this.decidedByName,
    this.decidedByRole,
    this.decidedAt,
    this.decisionRemarks,
  });

  bool get isPending => status == LeaveStatus.pending;

  /// Whether [dateKey] falls inside this request, whatever its status.
  /// String comparison works because the keys are zero-padded ISO dates.
  bool covers(String dateKey) =>
      dateKey.compareTo(fromDate) >= 0 && dateKey.compareTo(toDate) <= 0;
}
