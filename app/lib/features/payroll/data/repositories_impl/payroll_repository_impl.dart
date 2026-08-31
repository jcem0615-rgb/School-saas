import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/contribution_scheme.dart';
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
  Future<Result<int>> issuePayslips(List<Payslip> payslips) async {
    try {
      return Success(await _remote.issuePayslips(payslips));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
