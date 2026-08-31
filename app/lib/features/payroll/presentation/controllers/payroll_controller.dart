import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../../timekeeping/domain/entities/timesheet.dart';
import '../../../timekeeping/presentation/controllers/timekeeping_controller.dart'
    show TimesheetQuery, timesheetProvider;
import '../../data/datasources/payroll_remote_datasource.dart';
import '../../data/repositories_impl/payroll_repository_impl.dart';
import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payslip.dart';
import '../../domain/repositories/payroll_repository.dart';
import '../../domain/usecases/payroll_usecases.dart';

final payrollRemoteDataSourceProvider = Provider<PayrollRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('PayrollRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return PayrollRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingPayrollUser(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final payrollRepositoryProvider = Provider<PayrollRepository>((ref) {
  return PayrollRepositoryImpl(ref.watch(payrollRemoteDataSourceProvider));
});

final compensationStreamProvider =
    StreamProvider.autoDispose<List<Compensation>>((ref) {
  return ref.watch(payrollRepositoryProvider).watchCompensation();
});

/// The school's contribution and tax tables.
///
/// Not autoDispose: the payroll screen and the settings screen both need
/// it, and a run started the instant a screen opens must not compute
/// against a scheme that has not arrived.
final contributionSchemeProvider = StreamProvider<ContributionScheme>((ref) {
  return ref.watch(payrollRepositoryProvider).watchContributionScheme();
});

/// An employee's own payslips, for the copy they are entitled to.
final myPayslipsProvider = StreamProvider.autoDispose<List<Payslip>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream<List<Payslip>>.empty();
  return ref.watch(payrollRepositoryProvider).watchPayslips(employeeUid: uid);
});

final allPayslipsProvider = StreamProvider.autoDispose<List<Payslip>>((ref) {
  return ref.watch(payrollRepositoryProvider).watchPayslips();
});

/// What one employee's payslip would come to for a month.
///
/// A Provider rather than something the screen computes, because the run
/// screen shows a list of them and the detail screen shows one, and two
/// places computing somebody's pay is two places that can disagree about
/// it.
class PayrollDraftQuery {
  final Compensation compensation;
  final DateTime month;

  /// False on the first cut-off of a semi-monthly month, so the month's
  /// contributions are not taken twice.
  final bool deductContributions;

  const PayrollDraftQuery({
    required this.compensation,
    required this.month,
    this.deductContributions = true,
  });

  @override
  bool operator ==(Object other) =>
      other is PayrollDraftQuery &&
      other.compensation.employeeUid == compensation.employeeUid &&
      other.compensation.rate == compensation.rate &&
      other.compensation.basis == compensation.basis &&
      other.compensation.allowance == compensation.allowance &&
      other.compensation.deductAbsences == compensation.deductAbsences &&
      other.month.year == month.year &&
      other.month.month == month.month &&
      other.deductContributions == deductContributions;

  @override
  int get hashCode => Object.hash(
        compensation.employeeUid,
        compensation.rate,
        compensation.basis,
        compensation.allowance,
        compensation.deductAbsences,
        month.year,
        month.month,
        deductContributions,
      );
}

final payslipDraftProvider =
    Provider.autoDispose.family<Payslip?, PayrollDraftQuery>((ref, query) {
  final scheme = ref.watch(contributionSchemeProvider).valueOrNull;
  if (scheme == null) return null;

  final timesheet = ref.watch(timesheetProvider(TimesheetQuery(
    employeeUid: query.compensation.employeeUid,
    employeeName: query.compensation.employeeName,
    month: query.month,
  )));
  // Null while the scans are still arriving. An incomplete timesheet
  // looks exactly like a damning one, and computing pay off it would
  // dock somebody for a month of absences that were only a slow read.
  if (timesheet == null) return null;

  return computePayslip(
    compensation: query.compensation,
    timesheet: timesheet,
    scheme: scheme,
    // The tables are indexed by the monthly salary, not by what this
    // period pays. A semi-monthly payslip still deducts against the
    // monthly bracket.
    monthlyBasisForContributions: query.compensation.basis == PayBasis.monthly
        ? query.compensation.rate
        : query.compensation.rate * _assumedMonthlyUnits(query.compensation.basis),
    deductContributions: query.deductContributions,
  );
});

/// Turns a daily or hourly rate into the monthly figure the contribution
/// tables are read with.
///
/// Twenty-two working days, eight hours. Approximate on purpose and said
/// so: the alternative is asking every school to declare a divisor
/// before it can run payroll for one part-timer, and the bracket a
/// part-timer falls into is rarely close to a boundary.
double _assumedMonthlyUnits(PayBasis basis) =>
    basis == PayBasis.daily ? 22 : 22 * 8;

class PayrollActionController extends StateNotifier<AsyncValue<void>> {
  final PayrollRepository _repository;

  PayrollActionController(this._repository) : super(const AsyncData(null));

  Future<bool> saveCompensation(Compensation compensation) =>
      _run(() => SaveCompensationUseCase(_repository)(compensation));

  Future<bool> saveContributionScheme(ContributionScheme scheme) =>
      _run(() => SaveContributionSchemeUseCase(_repository)(scheme));

  Future<bool> confirmContributionScheme(ContributionScheme scheme) =>
      _run(() => ConfirmContributionSchemeUseCase(_repository)(scheme));

  Future<int?> issuePayslips({
    required List<Payslip> payslips,
    required ContributionScheme scheme,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result =
        await IssuePayslipsUseCase(_repository)(payslips: payslips, scheme: scheme);
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return null;
  }

  Future<bool> _run(Future<Result<void>> Function() action) async {
    if (mounted) state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final payrollActionControllerProvider =
    StateNotifierProvider.autoDispose<PayrollActionController, AsyncValue<void>>(
        (ref) {
  return PayrollActionController(ref.watch(payrollRepositoryProvider));
});
