import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firebaseFunctionsProvider, firestoreProvider;
import '../../data/datasources/payroll_remote_datasource.dart';
import '../../data/repositories_impl/payroll_repository_impl.dart';
import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payroll_run.dart';
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
    functions: ref.watch(firebaseFunctionsProvider),
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

/// A payroll period, as the run screen asks for it.
class PayrollRunQuery {
  /// Any date inside the month being run.
  final DateTime month;

  /// False on the first cut-off of a semi-monthly month, so the month's
  /// contributions are not taken twice.
  final bool deductContributions;

  const PayrollRunQuery({required this.month, this.deductContributions = true});

  DateTime get from => DateTime(month.year, month.month, 1);

  /// Day zero of the next month is the last day of this one, which is
  /// how February and the thirty-one-day months are handled without a
  /// table of month lengths or a leap-year rule.
  DateTime get to => DateTime(month.year, month.month + 1, 0);

  @override
  bool operator ==(Object other) =>
      other is PayrollRunQuery &&
      other.month.year == month.year &&
      other.month.month == month.month &&
      other.deductContributions == deductContributions;

  @override
  int get hashCode => Object.hash(month.year, month.month, deductContributions);
}

/// What the whole school's payroll comes to for a month.
///
/// The figures are the server's, computed by `runPayroll` with nothing
/// written -- and the same call with `commit` set is what issues them.
/// The point of that is what it rules out: a preview the office approves
/// and a set of payslips that came out of some other arithmetic.
///
/// Before this, the run was computed on the device from a timesheet the
/// device had assembled and written straight to Firestore. A screen that
/// had not finished loading somebody's scans would have paid them for a
/// month of absences.
final payrollPreviewProvider =
    FutureProvider.autoDispose.family<PayrollRun, PayrollRunQuery>((ref, query) async {
  final result = await RunPayrollUseCase(ref.watch(payrollRepositoryProvider))(
    periodFrom: query.from,
    periodTo: query.to,
    deductContributions: query.deductContributions,
    commit: false,
  );
  return switch (result) {
    Success(:final value) => value,
    Error(:final failure) => throw failure.message,
  };
});

class PayrollActionController extends StateNotifier<AsyncValue<void>> {
  final PayrollRepository _repository;

  PayrollActionController(this._repository) : super(const AsyncData(null));

  Future<bool> saveCompensation(Compensation compensation) =>
      _run(() => SaveCompensationUseCase(_repository)(compensation));

  Future<bool> saveContributionScheme(ContributionScheme scheme) =>
      _run(() => SaveContributionSchemeUseCase(_repository)(scheme));

  Future<bool> confirmContributionScheme(ContributionScheme scheme) =>
      _run(() => ConfirmContributionSchemeUseCase(_repository)(scheme));

  /// Issues the run. Returns how many payslips were written, or null
  /// when the server refused -- in which case the reason is on [state].
  Future<int?> issuePayroll(PayrollRunQuery query) async {
    if (mounted) state = const AsyncLoading();
    final result = await RunPayrollUseCase(_repository)(
      periodFrom: query.from,
      periodTo: query.to,
      deductContributions: query.deductContributions,
      commit: true,
    );
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value.issued;
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
