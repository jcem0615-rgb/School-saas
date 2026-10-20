import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../models/ledger_models.dart';

class ActingBookkeeper {
  final String uid;
  final String schoolId;
  final String name;
  const ActingBookkeeper({
    required this.uid,
    required this.schoolId,
    required this.name,
  });
}

/// Reads the books; never writes an entry.
///
/// Every journal write goes through a callable, because firestore.rules
/// refuses client writes to `journalEntries` outright -- rules cannot sum
/// an array, so there is no way to prove there that an entry balances.
/// The chart of accounts is an ordinary write: it is a list of names, and
/// rules can check everything that matters about it.
class LedgerRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingBookkeeper _actingUser;

  const LedgerRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingBookkeeper actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  Stream<List<LedgerAccountModel>> watchChartOfAccounts() {
    return _firestore
        .collection(FirestorePaths.ledgerAccounts(_actingUser.schoolId))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LedgerAccountModel.fromFirestore(d.id, d.data()))
            .toList()
          ..sort((a, b) {
            final byType = a.type.sortOrder.compareTo(b.type.sortOrder);
            return byType != 0 ? byType : a.code.compareTo(b.code);
          }));
  }

  Stream<List<JournalEntryModel>> watchJournal(LedgerPeriod period) {
    return _firestore
        .collection(FirestorePaths.journalEntries(_actingUser.schoolId))
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(period.from))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(period.to))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => JournalEntryModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Every entry touching one account.
  ///
  /// Filtered in the client rather than the query: Firestore cannot ask
  /// "where any element of this array of maps has accountCode = X", and
  /// the alternative is a second collection of postings kept in step with
  /// the entries -- a second truth, which is the thing this ledger exists
  /// to avoid. A school year of entries is a few thousand documents, and
  /// this screen is opened by two people.
  Stream<List<JournalEntryModel>> watchAccountLedger({
    required String accountCode,
    required LedgerPeriod period,
  }) {
    return watchJournal(period).map((entries) => entries
        .where((e) => e.lines.any((l) => l.accountCode == accountCode))
        .toList());
  }

  Future<void> addAccount(LedgerAccount account) async {
    await _firestore
        .doc(FirestorePaths.ledgerAccountDoc(_actingUser.schoolId, account.code))
        .set({
      'code': account.code,
      'name': account.name,
      'type': account.type.value,
      'isSystem': false,
      'isActive': true,
      'description': account.description,
      'schoolId': _actingUser.schoolId,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _actingUser.uid,
      'isDeleted': false,
    });
  }

  Future<void> updateAccount({
    required String code,
    String? name,
    String? description,
    bool? isActive,
  }) async {
    await _firestore
        .doc(FirestorePaths.ledgerAccountDoc(_actingUser.schoolId, code))
        .update({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<String> postManualEntry({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  }) async {
    final callable = _functions.httpsCallable('postManualEntry');
    final result = await callable.call<Map<String, dynamic>>({
      'schoolId': _actingUser.schoolId,
      'date': date.toIso8601String(),
      'memo': memo,
      'lines': [
        for (final line in lines)
          {
            'accountCode': line.accountCode,
            if (line.debit > 0) 'debit': line.debit,
            if (line.credit > 0) 'credit': line.credit,
            if (line.memo != null) 'memo': line.memo,
          },
      ],
    });
    return result.data['entryNumber'] as String? ?? '';
  }

  Future<String> reverseEntry({
    required String entryId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('reverseJournalEntry');
    final result = await callable.call<Map<String, dynamic>>({
      'schoolId': _actingUser.schoolId,
      'entryId': entryId,
      'reason': reason,
    });
    return result.data['entryNumber'] as String? ?? '';
  }
}
