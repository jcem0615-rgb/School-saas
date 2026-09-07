import '../../../../core/errors/result.dart';
import '../entities/contribution_scheme.dart';
import '../entities/payroll_run.dart';
import '../entities/payslip.dart';

abstract class PayrollRepository {
  /// What everybody is paid. The whole list, because a payroll run needs
  /// all of it at once and a school has tens of employees, not thousands.
  Stream<List<Compensation>> watchCompensation();

  Future<Result<void>> saveCompensation(Compensation compensation);

  /// The school's contribution and tax tables.
  Stream<ContributionScheme> watchContributionScheme();

  /// Replaces the tables. Revokes the confirmation, for the same reason
  /// the grading scheme does: a table somebody confirmed in January and
  /// somebody else edited in June is not a confirmed table.
  Future<Result<void>> saveContributionScheme(ContributionScheme scheme);

  Future<Result<void>> confirmContributionScheme();

  /// Payslips already issued, newest first. Scoped by the rules: an
  /// employee sees their own, Director and Admin see everybody's.
  Stream<List<Payslip>> watchPayslips({String? employeeUid});

  /// Runs payroll for a period, on the server.
  ///
  /// [commit] false previews and writes nothing; true issues. Both are
  /// the same call, so the figures the office approved are the figures
  /// that go into the record rather than a second computation that has
  /// to be kept in step with the first.
  ///
  /// Nothing about the money is passed in. The pay rates, the
  /// contribution tables, the scans and the approved leave are all read
  /// server-side -- this side supplies a period and which cut-off it is,
  /// which is all it is in a position to know.
  Future<Result<PayrollRun>> runPayroll({
    required DateTime periodFrom,
    required DateTime periodTo,
    required bool deductContributions,
    required bool commit,
  });
}
