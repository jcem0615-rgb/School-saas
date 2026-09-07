import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../timekeeping/domain/entities/timesheet.dart' show dateKeyOf;
import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payroll_run.dart';
import '../../domain/entities/payslip.dart';
import '../../domain/repositories/payroll_repository.dart';
import '../datasources/payroll_remote_datasource.dart';

class PayrollRepositoryImpl implements PayrollRepository {
  final PayrollRemoteDataSource _remote;
  const PayrollRepositoryImpl(this._remote);

  @override
  Stream<List<Compensation>> watchCompensation() => _remote.watchCompensation();

  @override
  Stream<ContributionScheme> watchContributionScheme() =>
      _remote.watchContributionScheme();

  @override
  Stream<List<Payslip>> watchPayslips({String? employeeUid}) =>
      _remote.watchPayslips(employeeUid: employeeUid);

  @override
  Future<Result<void>> saveCompensation(Compensation compensation) async {
    try {
      await _remote.saveCompensation(compensation);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> saveContributionScheme(ContributionScheme scheme) async {
    try {
      await _remote.saveContributionScheme(scheme);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> confirmContributionScheme() async {
    try {
      await _remote.confirmContributionScheme();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<PayrollRun>> runPayroll({
    required DateTime periodFrom,
    required DateTime periodTo,
    required bool deductContributions,
    required bool commit,
  }) async {
    try {
      return Success(await _remote.runPayroll(
        periodFrom: dateKeyOf(periodFrom),
        periodTo: dateKeyOf(periodTo),
        deductContributions: deductContributions,
        commit: commit,
      ));
    } on ServerException catch (e) {
      // Carried through rather than flattened to "something went wrong".
      // The server's refusals name who has already been paid for this
      // period and which agency still has no table, and those are the
      // only things the office can act on.
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
