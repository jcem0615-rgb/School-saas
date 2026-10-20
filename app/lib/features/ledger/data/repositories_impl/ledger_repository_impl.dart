import 'package:cloud_firestore/cloud_firestore.dart';
// `Result` is also a cloud_functions type. Hidden rather than
// prefixed so the Result in this file is unambiguously the app's.
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../datasources/ledger_remote_datasource.dart';

class LedgerRepositoryImpl implements LedgerRepository {
  final LedgerRemoteDataSource _remote;
  const LedgerRepositoryImpl(this._remote);

  @override
  Stream<List<LedgerAccount>> watchChartOfAccounts() =>
      _remote.watchChartOfAccounts();

  @override
  Stream<List<JournalEntry>> watchJournal(LedgerPeriod period) =>
      _remote.watchJournal(period);

  @override
  Stream<List<JournalEntry>> watchAccountLedger({
    required String accountCode,
    required LedgerPeriod period,
  }) =>
      _remote.watchAccountLedger(accountCode: accountCode, period: period);

  @override
  Future<Result<void>> addAccount(LedgerAccount account) =>
      _guard(() => _remote.addAccount(account), 'The account could not be added.');

  @override
  Future<Result<void>> updateAccount({
    required String code,
    String? name,
    String? description,
    bool? isActive,
  }) =>
      _guard(
        () => _remote.updateAccount(
          code: code,
          name: name,
          description: description,
          isActive: isActive,
        ),
        'The account could not be changed.',
      );

  @override
  Future<Result<String>> postManualEntry({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  }) =>
      _guardValue(
        () => _remote.postManualEntry(date: date, memo: memo, lines: lines),
        'The entry could not be posted.',
      );

  @override
  Future<Result<String>> reverseEntry({
    required String entryId,
    required String reason,
  }) =>
      _guardValue(
        () => _remote.reverseEntry(entryId: entryId, reason: reason),
        'The entry could not be reversed.',
      );

  Future<Result<void>> _guard(Future<void> Function() run, String fallback) async {
    final result = await _guardValue(() async {
      await run();
      return '';
    }, fallback);
    return result.map((_) {});
  }

  /// One place that turns a thrown error into a sentence.
  ///
  /// The callables refuse with `invalid-argument` for a bad entry and
  /// `failed-precondition` for one that cannot be posted now -- an entry
  /// already reversed, an account switched off. Both carry a message
  /// written for the person who tried, so they are passed through rather
  /// than replaced with something vaguer.
  Future<Result<String>> _guardValue(
    Future<String> Function() run,
    String fallback,
  ) async {
    try {
      return Success(await run());
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'Only the Director or an Admin can post to the books.',
        ));
      }
      return Error(ValidationFailure(e.message ?? fallback));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'This account cannot read or change the books.',
        ));
      }
      return Error(ServerFailure(e.message ?? fallback));
    } catch (_) {
      return Error(UnknownFailure(fallback));
    }
  }
}
