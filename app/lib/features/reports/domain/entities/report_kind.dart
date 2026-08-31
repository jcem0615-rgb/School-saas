/// The reports this module knows how to produce.
///
/// Each one declares what it needs to read, so opening the enrollment
/// report does not pull a term of attendance scans across the wire to
/// answer a question about the roll.
enum ReportKind {
  enrollment(
    'Enrollment by Division',
    'Head count by division and grade level, every status shown.',
    needsStudents: true,
    usesPeriod: false,
  ),
  collections(
    'Collections and Receivables',
    'What was charged, what came in, and what is still owed.',
    needsStudents: true,
    needsPayments: true,
    needsAssessments: true,
  ),
  overdue(
    'Overdue Accounts',
    'Who is behind on their payment plan, and by how many days.',
    needsStudents: true,
    needsPayments: true,
    needsAssessments: true,
    // A snapshot of today, like the enrollment roll. "Who was overdue in
    // March" is a different question, and it needs a history of
    // instalments and payments this system does not keep -- offering a
    // date range beside it would promise one.
    usesPeriod: false,
  ),
  discounts(
    'Discounts and Scholarships',
    'What the school gave away, by kind, and to how many students.',
    needsStudents: true,
    needsAssessments: true,
  ),
  subsidyClaims(
    'ESC and Voucher Claims',
    'Every government grant the school can bill for, with its certificate.',
    needsStudents: true,
    needsAssessments: true,
  ),
  attendance(
    'Attendance Rate by Section',
    'Present, late and absent by section, with the rate.',
    needsStudents: true,
    needsAttendance: true,
  ),
  grades(
    'Grade Distribution by Subject',
    'Marks banded against the DepEd descriptors.',
    needsGrades: true,
  );

  final String title;
  final String blurb;
  final bool needsStudents;
  final bool needsPayments;
  final bool needsAssessments;
  final bool needsAttendance;
  final bool needsGrades;

  /// Whether the date range means anything here. Enrollment is a head
  /// count taken today; offering a date picker beside it would promise a
  /// historical roll this system does not keep.
  final bool usesPeriod;

  const ReportKind(
    this.title,
    this.blurb, {
    this.needsStudents = false,
    this.needsPayments = false,
    this.needsAssessments = false,
    this.needsAttendance = false,
    this.needsGrades = false,
    this.usesPeriod = true,
  });
}
