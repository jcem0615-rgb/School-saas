import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/journal_entry.dart';
import '../entities/ledger_account.dart';
import '../repositories/ledger_repository.dart';

class WatchChartOfAccountsUseCase {
  final LedgerRepository _repository;
  const WatchChartOfAccountsUseCase(this._repository);

  Stream<List<LedgerAccount>> call() => _repository.watchChartOfAccounts();
}

class WatchJournalUseCase {
  final LedgerRepository _repository;
  const WatchJournalUseCase(this._repository);

  Stream<List<JournalEntry>> call(LedgerPeriod period) =>
      _repository.watchJournal(period);
}

class WatchAccountLedgerUseCase {
  final LedgerRepository _repository;
  const WatchAccountLedgerUseCase(this._repository);

  Stream<List<JournalEntry>> call({
    required String accountCode,
    required LedgerPeriod period,
  }) =>
      _repository.watchAccountLedger(accountCode: accountCode, period: period);
}

/// Adds an account to the chart.
///
/// The code has to be free, numeric, and in the block its type owns --
/// assets in the 1000s, liabilities in the 2000s, and so on. A school
/// that files a new expense account under 1500 gets a balance sheet with
/// its light bill listed as an asset, and finds out months later.
class AddLedgerAccountUseCase {
  final LedgerRepository _repository;
  const AddLedgerAccountUseCase(this._repository);

  /// The first digit each type owns, by the convention every chart of
  /// accounts in the country already follows.
  static const blockFor = <AccountType, String>{
    AccountType.asset: '1',
    AccountType.liability: '2',
    AccountType.equity: '3',
    AccountType.revenue: '4',
    AccountType.expense: '5',
  };

  Future<Result<void>> call({
    required String code,
    required String name,
    required AccountType type,
    String? description,
    required Iterable<LedgerAccount> existing,
  }) {
    final trimmedCode = code.trim();
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return Future.value(const Error(ValidationFailure('Give the account a name.')));
    }
    if (!RegExp(r'^\d{4}$').hasMatch(trimmedCode)) {
      return Future.value(const Error(
        ValidationFailure('An account code is four digits, like 5400.'),
      ));
    }
    final block = blockFor[type]!;
    if (!trimmedCode.startsWith(block)) {
      return Future.value(Error(ValidationFailure(
        '${type.groupLabel} are numbered in the ${block}000s. '
        'A code outside its own block puts the account in the wrong half '
        'of the balance sheet.',
      )));
    }
    if (existing.any((a) => a.code == trimmedCode)) {
      return Future.value(Error(ValidationFailure(
        'Account $trimmedCode already exists.',
      )));
    }

    return _repository.addAccount(LedgerAccount(
      code: trimmedCode,
      name: trimmedName,
      type: type,
      description: description?.trim().isEmpty ?? true ? null : description!.trim(),
    ));
  }
}

/// Renames an account, or takes it out of use.
class UpdateLedgerAccountUseCase {
  final LedgerRepository _repository;
  const UpdateLedgerAccountUseCase(this._repository);

  Future<Result<void>> call({
    required LedgerAccount account,
    String? name,
    String? description,
    bool? isActive,
  }) {
    if (name != null && name.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Give the account a name.')));
    }
    // A system account may be renamed -- a school that calls 4010 "Other
    // School Fees" should see that everywhere -- but never switched off,
    // because the automatic postings find it by code.
    if (account.isSystem && isActive == false) {
      return Future.value(Error(ValidationFailure(
        '${account.label} is posted to automatically and cannot be '
        'deactivated. Rename it instead.',
      )));
    }
    return _repository.updateAccount(
      code: account.code,
      name: name?.trim(),
      description: description?.trim(),
      isActive: isActive,
    );
  }
}

/// Posts an entry a person wrote.
///
/// Opening balances, a correction an auditor asked for, the depreciation
/// nobody has automated. Everything with an event behind it is posted by
/// that event instead.
class PostManualEntryUseCase {
  final LedgerRepository _repository;
  const PostManualEntryUseCase(this._repository);

  Future<Result<String>> call({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  }) {
    final said = memo.trim();
    if (said.length < 4) {
      // A hand-written entry with no explanation is the one thing an
      // auditor will ask about, and the one thing nobody will remember.
      return Future.value(const Error(
        ValidationFailure('Say what this entry is for.'),
      ));
    }
    // A date in the future is almost always a typo in the year, and it
    // puts the entry outside every period anyone will look at.
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      return Future.value(const Error(
        ValidationFailure('An entry cannot be dated in the future.'),
      ));
    }
    final problem = reasonEntryCannotPost(lines);
    if (problem != null) {
      return Future.value(Error(ValidationFailure(problem)));
    }
    return _repository.postManualEntry(date: date, memo: said, lines: lines);
  }
}

/// Reverses an entry.
///
/// The only correction there is. Posting the opposite leaves both the
/// mistake and the fix on the record, which is what an accounting office
/// does with a paper journal and for the same reason.
class ReverseEntryUseCase {
  final LedgerRepository _repository;
  const ReverseEntryUseCase(this._repository);

  Future<Result<String>> call({
    required JournalEntry entry,
    required String reason,
  }) {
    final why = reason.trim();
    if (why.length < 4) {
      return Future.value(const Error(
        ValidationFailure('Say why it is being reversed.'),
      ));
    }
    if (entry.isReversed) {
      return Future.value(Error(ValidationFailure(
        'Entry ${entry.entryNumber} has already been reversed.',
      )));
    }
    if (entry.isReversal) {
      // Reversing a reversal is how a journal turns into a tangle nobody
      // can read. If the reversal was wrong, post the original again.
      return Future.value(Error(ValidationFailure(
        'Entry ${entry.entryNumber} is itself a reversal. Post a fresh '
        'entry instead of reversing it.',
      )));
    }
    return _repository.reverseEntry(entryId: entry.id, reason: why);
  }
}
