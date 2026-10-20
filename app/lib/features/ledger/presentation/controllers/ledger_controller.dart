import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/ledger_remote_datasource.dart';
import '../../data/repositories_impl/ledger_repository_impl.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../../domain/usecases/ledger_usecases.dart';

final ledgerRemoteDataSourceProvider = Provider<LedgerRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('LedgerRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return LedgerRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingBookkeeper(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepositoryImpl(ref.watch(ledgerRemoteDataSourceProvider));
});

/// Which stretch of time the books are being read over.
///
/// A school year by default, because that is the period a school reports
/// on. Defaults to the one that is running: June onwards is this year's,
/// anything earlier still belongs to the year that started last June.
final ledgerPeriodProvider = StateProvider<LedgerPeriod>((ref) {
  final now = DateTime.now();
  return LedgerPeriod.schoolYear(now.month >= 6 ? now.year : now.year - 1);
});

final chartOfAccountsProvider =
    StreamProvider.autoDispose<List<LedgerAccount>>((ref) {
  return WatchChartOfAccountsUseCase(ref.watch(ledgerRepositoryProvider))();
});

final journalProvider = StreamProvider.autoDispose<List<JournalEntry>>((ref) {
  return WatchJournalUseCase(ref.watch(ledgerRepositoryProvider))(
    ref.watch(ledgerPeriodProvider),
  );
});

final accountLedgerProvider =
    StreamProvider.autoDispose.family<List<JournalEntry>, String>((ref, code) {
  return WatchAccountLedgerUseCase(ref.watch(ledgerRepositoryProvider))(
    accountCode: code,
    period: ref.watch(ledgerPeriodProvider),
  );
});

/// The trial balance, built in the app from the chart and the journal.
///
/// Derived rather than stored, which is the point: a stored total is a
/// second truth that drifts the first time an entry is posted by
/// something that forgot to update it.
final trialBalanceProvider = Provider.autoDispose<TrialBalance?>((ref) {
  final chart = ref.watch(chartOfAccountsProvider).valueOrNull;
  final entries = ref.watch(journalProvider).valueOrNull;
  if (chart == null || entries == null) return null;
  return TrialBalance.from(
    chart: chart,
    entries: entries,
    asOf: ref.watch(ledgerPeriodProvider).to,
  );
});

final ledgerActionControllerProvider =
    StateNotifierProvider.autoDispose<LedgerActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return LedgerActionController(
    addAccount: AddLedgerAccountUseCase(repo),
    updateAccount: UpdateLedgerAccountUseCase(repo),
    postManualEntry: PostManualEntryUseCase(repo),
    reverseEntry: ReverseEntryUseCase(repo),
  );
});

class LedgerActionController extends StateNotifier<AsyncValue<void>> {
  final AddLedgerAccountUseCase _addAccount;
  final UpdateLedgerAccountUseCase _updateAccount;
  final PostManualEntryUseCase _postManualEntry;
  final ReverseEntryUseCase _reverseEntry;

  LedgerActionController({
    required AddLedgerAccountUseCase addAccount,
    required UpdateLedgerAccountUseCase updateAccount,
    required PostManualEntryUseCase postManualEntry,
    required ReverseEntryUseCase reverseEntry,
  })  : _addAccount = addAccount,
        _updateAccount = updateAccount,
        _postManualEntry = postManualEntry,
        _reverseEntry = reverseEntry,
        super(const AsyncData(null));

  Future<bool> addAccount({
    required String code,
    required String name,
    required AccountType type,
    String? description,
    required Iterable<LedgerAccount> existing,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _addAccount(
      code: code,
      name: name,
      type: type,
      description: description,
      existing: existing,
    ));
  }

  Future<bool> updateAccount({
    required LedgerAccount account,
    String? name,
    String? description,
    bool? isActive,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _updateAccount(
      account: account,
      name: name,
      description: description,
      isActive: isActive,
    ));
  }

  /// Returns the entry number so it can be said back: "posted as
  /// JE-2026-0042" is what somebody writes on the voucher.
  Future<String?> postManualEntry({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settleValue(
      await _postManualEntry(date: date, memo: memo, lines: lines),
    );
  }

  Future<String?> reverseEntry({
    required JournalEntry entry,
    required String reason,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settleValue(await _reverseEntry(entry: entry, reason: reason));
  }

  bool _settle(Result<void> result) => switch (result) {
        Success() => () {
            if (mounted) state = const AsyncData(null);
            return true;
          }(),
        Error(:final failure) => () {
            if (mounted) state = AsyncError(failure.message, StackTrace.current);
            return false;
          }(),
      };

  String? _settleValue(Result<String> result) => switch (result) {
        Success(:final value) => () {
            if (mounted) state = const AsyncData(null);
            return value;
          }(),
        Error(:final failure) => () {
            if (mounted) state = AsyncError(failure.message, StackTrace.current);
            return null;
          }(),
      };
}
