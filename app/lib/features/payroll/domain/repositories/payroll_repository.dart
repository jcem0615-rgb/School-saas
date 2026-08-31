import '../../../../core/errors/result.dart';
import '../entities/contribution_scheme.dart';
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

  /// Writes a run's payslips. Append-only; a correction is a new one.
  Future<Result<int>> issuePayslips(List<Payslip> payslips);
}
