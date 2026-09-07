import 'payslip.dart';

/// One payroll run, as the server worked it out.
///
/// The preview the office approves and the payslips it then issues are
/// the same call with one flag flipped, so this is the shape of both.
/// That is the point of it: what the screen showed and what went into
/// the record are not two computations that have to be kept in step.
class PayrollRun {
  /// Every payslip in the run, whether or not it was written.
  final List<Payslip> payslips;

  /// True when this run was issued rather than previewed.
  final bool committed;

  /// How many payslips were written. Zero for a preview.
  final int issued;

  /// Whether the school's contribution tables are filled in and
  /// confirmed. False means [blockers] says what is missing.
  final bool canIssue;

  /// What stands between this run and being issued, in the words the
  /// server would refuse it with.
  final List<String> blockers;

  const PayrollRun({
    required this.payslips,
    required this.committed,
    required this.issued,
    required this.canIssue,
    required this.blockers,
  });

  static const empty = PayrollRun(
    payslips: [],
    committed: false,
    issued: 0,
    canIssue: false,
    blockers: [],
  );

  double get totalNetPay =>
      payslips.fold<double>(0, (sum, p) => sum + p.netPay);

  /// The school's own share, which never appears on a payslip and is
  /// money it has to have.
  double get totalEmployerContributions =>
      payslips.fold<double>(0, (sum, p) => sum + p.employerContributions);

  int get incompleteHours => payslips.where((p) => p.hoursAreIncomplete).length;
}
