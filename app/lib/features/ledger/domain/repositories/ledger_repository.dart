import '../../../../core/errors/result.dart';
import '../entities/journal_entry.dart';
import '../entities/ledger_account.dart';

/// A window of time the books are read over.
///
/// A school year rather than a calendar one, most of the time, which is
/// why this is a pair of dates and not a year.
class LedgerPeriod {
  final DateTime from;
  final DateTime to;
  final String label;

  const LedgerPeriod({required this.from, required this.to, required this.label});

  /// The school year as Philippine schools run it: June to March, named
  /// for the two calendar years it spans.
  factory LedgerPeriod.schoolYear(int startYear) => LedgerPeriod(
        from: DateTime(startYear, 6, 1),
        to: DateTime(startYear + 1, 5, 31, 23, 59, 59),
        label: '$startYear-${startYear + 1}',
      );

  factory LedgerPeriod.month(DateTime day) {
    final from = DateTime(day.year, day.month, 1);
    final to = DateTime(day.year, day.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    return LedgerPeriod(from: from, to: to, label: '${day.year}-${day.month}');
  }

  bool holds(DateTime when) => !when.isBefore(from) && !when.isAfter(to);
}

abstract class LedgerRepository {
  /// The chart of accounts, in the order a bookkeeper reads it.
  Stream<List<LedgerAccount>> watchChartOfAccounts();

  /// Entries posted in a period, newest first.
  Stream<List<JournalEntry>> watchJournal(LedgerPeriod period);

  /// Every entry touching one account, for drilling into a trial balance
  /// figure that looks wrong.
  Stream<List<JournalEntry>> watchAccountLedger({
    required String accountCode,
    required LedgerPeriod period,
  });

  /// Adds an account the school needs and the standard chart does not
  /// have. The code is theirs to choose, within the range its type owns.
  Future<Result<void>> addAccount(LedgerAccount account);

  /// Renames an account or takes it out of use.
  ///
  /// A system account may be renamed but never deactivated: the postings
  /// reference it by code and a payment next week has to find it.
  Future<Result<void>> updateAccount({
    required String code,
    String? name,
    String? description,
    bool? isActive,
  });

  /// Posts an entry somebody wrote by hand.
  ///
  /// Everything else is posted by the thing that caused it, server-side,
  /// inside the transaction that wrote the payment or the payslip. This
  /// is for the opening balances and the adjustments that have no event
  /// behind them.
  Future<Result<String>> postManualEntry({
    required DateTime date,
    required String memo,
    required List<JournalLine> lines,
  });

  /// Posts the reverse of an entry, and marks the original as reversed.
  ///
  /// The only way to undo anything in here.
  Future<Result<String>> reverseEntry({
    required String entryId,
    required String reason,
  });
}
