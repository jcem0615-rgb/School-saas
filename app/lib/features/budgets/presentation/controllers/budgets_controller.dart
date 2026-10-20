import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../../ledger/domain/entities/ledger_account.dart';
import '../../../ledger/presentation/controllers/ledger_controller.dart'
    show chartOfAccountsProvider, ledgerPeriodProvider, trialBalanceProvider;
import '../../data/budgets_repository_impl.dart';
import '../../domain/entities/budget.dart';

final budgetsRepositoryProvider = Provider<BudgetsRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('BudgetsRepository requires a signed-in, school-scoped user.');
  }
  return BudgetsRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingPlanner(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

/// The school year being planned, which follows the ledger's period so
/// the budget and the books are never looking at different years.
final budgetYearProvider = Provider.autoDispose<String>((ref) {
  return ref.watch(ledgerPeriodProvider).label;
});

final budgetsProvider = StreamProvider.autoDispose<List<Budget>>((ref) {
  return ref.watch(budgetsRepositoryProvider).watchBudgets(ref.watch(budgetYearProvider));
});

/// The plan next to the books.
///
/// Null until both have arrived: a report built from budgets and an
/// empty trial balance would show every line as unspent, which is the
/// most misleading thing it could say.
final budgetReportProvider = Provider.autoDispose<BudgetReport?>((ref) {
  final budgets = ref.watch(budgetsProvider).valueOrNull;
  final books = ref.watch(trialBalanceProvider);
  if (budgets == null || books == null) return null;
  return BudgetReport.from(
    schoolYear: ref.watch(budgetYearProvider),
    budgets: budgets,
    books: books,
  );
});

/// Whether spending [amount] on [accountCode] would go past its
/// allowance -- asked by the bill screen before anything is committed.
///
/// A warning, never a block. A school that cannot record the electricity
/// bill because somebody budgeted too little does not thereby spend
/// less; it just has a liability nobody can see.
String? budgetWarningFor({
  required BudgetReport? report,
  required String accountCode,
  required double amount,
}) {
  final line = report?.lineFor(accountCode);
  if (line == null) return null;
  if (!line.isBudgeted) {
    return line.actual > 0 || amount > 0
        ? '${line.accountName} has no budget for this year.'
        : null;
  }
  if (!line.wouldBreachWith(amount)) return null;
  final over = (line.actual + amount) - line.budgeted;
  return '${line.accountName} would go ${over.toStringAsFixed(2)} over its '
      'budget for the year.';
}

final budgetsActionControllerProvider =
    StateNotifierProvider.autoDispose<BudgetsActionController, AsyncValue<void>>((ref) {
  return BudgetsActionController(
    repository: ref.watch(budgetsRepositoryProvider),
    chart: ref.watch(chartOfAccountsProvider).valueOrNull ?? const [],
    schoolYear: ref.watch(budgetYearProvider),
  );
});

class BudgetsActionController extends StateNotifier<AsyncValue<void>> {
  final BudgetsRepository _repository;
  final List<LedgerAccount> _chart;
  final String _schoolYear;

  BudgetsActionController({
    required BudgetsRepository repository,
    required List<LedgerAccount> chart,
    required String schoolYear,
  })  : _repository = repository,
        _chart = chart,
        _schoolYear = schoolYear,
        super(const AsyncData(null));

  Future<bool> setBudget({
    required String accountCode,
    required double amount,
    String? note,
  }) async {
    final account = _chart.where((a) => a.code == accountCode).firstOrNull;
    final problem = reasonBudgetCannotBeSet(
      schoolYear: _schoolYear,
      account: account,
      amount: amount,
    );
    if (problem != null) {
      if (mounted) state = AsyncError(problem, StackTrace.current);
      return false;
    }

    if (mounted) state = const AsyncLoading();
    final result = await _repository.setBudget(Budget(
      schoolYear: _schoolYear,
      accountCode: account!.code,
      accountName: account.name,
      amount: amount,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      // Both are overwritten server-side by the repository; they are
      // here because the entity cannot be built without them.
      setByName: '',
      setAt: DateTime.now(),
    ));

    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final Failure failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }
}
