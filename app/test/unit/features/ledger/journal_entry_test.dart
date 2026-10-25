import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/ledger/domain/entities/journal_entry.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';

/// Double-entry bookkeeping, which is three rules and a lot of
/// consequences: every entry balances, every account knows which side it
/// grows on, and nothing is ever edited.
void main() {
  JournalEntry entry({
    String id = 'je_1',
    String number = 'JE-2026-0001',
    required List<JournalLine> lines,
    EntrySource source = EntrySource.payment,
    DateTime? on,
    String? reversalOf,
    String? reversedBy,
  }) =>
      JournalEntry(
        id: id,
        entryNumber: number,
        date: on ?? DateTime(2026, 7, 2),
        memo: 'Tuition - Juan Dela Cruz',
        source: source,
        sourceId: 'pay_1',
        lines: lines,
        postedByName: 'Grace Mendoza',
        postedAt: on ?? DateTime(2026, 7, 2),
        reversalOf: reversalOf,
        reversedBy: reversedBy,
      );

  /// A tuition payment, as the product posts one.
  List<JournalLine> tuitionPayment(double amount) => [
        JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', amount),
        JournalLine.credit(
            Accounts.receivableStudents, 'Accounts Receivable - Students', amount),
      ];

  group('a line is one side or the other', () {
    test('a debit line is a debit and nothing else', () {
      final line = JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 1500);
      expect(line.isDebit, isTrue);
      expect(line.credit, 0);
      expect(line.amount, 1500);
      expect(line.isWellFormed, isTrue);
    });

    test('a line that is both, or neither, is malformed', () {
      // Storing both as nullable numbers and letting one be zero is how
      // you get a line that means nothing and a total that still adds up.
      const both = JournalLine(
          accountCode: '1000', accountName: 'Cash on Hand', debit: 10, credit: 10);
      const neither =
          JournalLine(accountCode: '1000', accountName: 'Cash on Hand');
      const negative = JournalLine(
          accountCode: '1000', accountName: 'Cash on Hand', debit: -10);
      const nameless = JournalLine(accountCode: '  ', accountName: 'x', debit: 10);

      expect(both.isWellFormed, isFalse);
      expect(neither.isWellFormed, isFalse);
      expect(negative.isWellFormed, isFalse);
      expect(nameless.isWellFormed, isFalse);
    });
  });

  group('an entry has to balance', () {
    test('a balanced pair posts', () {
      expect(reasonEntryCannotPost(tuitionPayment(1500)), isNull);
    });

    test('an unbalanced entry says by how much', () {
      // Shown to the person who tried. "This entry is invalid" is not
      // worth saying; "debits and credits differ by 500.00" is.
      final reason = reasonEntryCannotPost([
        JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 1500),
        JournalLine.credit(Accounts.revenueTuition, 'Tuition Revenue', 1000),
      ]);

      expect(reason, isNotNull);
      expect(reason, contains('500.00'));
    });

    test('one line is not an entry', () {
      final reason = reasonEntryCannotPost([
        JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 1500),
      ]);
      expect(reason, contains('at least two lines'));
    });

    test('an entry of nothing is refused', () {
      final reason = reasonEntryCannotPost([
        const JournalLine(accountCode: '1000', accountName: 'Cash on Hand'),
        const JournalLine(accountCode: '4000', accountName: 'Tuition Revenue'),
      ]);
      expect(reason, isNotNull);
    });

    test('a residue of centavos still balances', () {
      // The reason money is compared to the nearest centavo rather than
      // with ==: 0.1 + 0.2 is not 0.3 in binary floating point, and a
      // trial balance is exactly where that shows up. Three shares of
      // 1000/3 is the case a school actually hits, splitting a fee.
      const third = 1000 / 3;
      expect(
        reasonEntryCannotPost([
          JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 1000),
          JournalLine.credit(Accounts.revenueTuition, 'Tuition Revenue', third),
          JournalLine.credit(Accounts.revenueMiscFees, 'Miscellaneous Fees', third),
          JournalLine.credit(Accounts.revenueOther, 'Other Income', third),
        ]),
        isNull,
      );
    });

    test('a peso out does not balance', () {
      expect(
        reasonEntryCannotPost([
          JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 1000),
          JournalLine.credit(Accounts.revenueTuition, 'Tuition Revenue', 999),
        ]),
        isNotNull,
      );
    });
  });

  group('which side an account grows on', () {
    test('assets and expenses grow on the debit side', () {
      expect(AccountType.asset.increasesOnDebit, isTrue);
      expect(AccountType.expense.increasesOnDebit, isTrue);
      expect(AccountType.liability.increasesOnDebit, isFalse);
      expect(AccountType.equity.increasesOnDebit, isFalse);
      expect(AccountType.revenue.increasesOnDebit, isFalse);
    });

    test('a balance reads positive in the direction it runs', () {
      // "Cash on Hand: 48,200" has to mean the school has it, not that
      // the debits exceeded the credits by that much -- same number,
      // worse sentence.
      const cash = LedgerAccount(
          code: '1000', name: 'Cash on Hand', type: AccountType.asset);
      const revenue = LedgerAccount(
          code: '4000', name: 'Tuition Revenue', type: AccountType.revenue);

      expect(
        const AccountBalance(account: cash, debits: 50000, credits: 1800).balance,
        48200,
      );
      expect(
        const AccountBalance(account: revenue, debits: 0, credits: 48200).balance,
        48200,
      );
    });
  });

  group('the trial balance', () {
    test('adds up, and says so', () {
      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [
          entry(id: 'a', lines: tuitionPayment(1500)),
          entry(id: 'b', lines: tuitionPayment(2500)),
        ],
      );

      expect(trial.balances, isTrue);
      expect(trial.totalDebits, 4000);
      expect(trial.totalCredits, 4000);
    });

    test('an account nothing was posted to is kept off it', () {
      // A school's chart always has a few, and they are noise on a page
      // whose whole job is to be scanned.
      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [entry(lines: tuitionPayment(1500))],
      );

      expect(trial.posted, hasLength(2));
      expect(
        trial.posted.map((r) => r.account.code),
        containsAll([Accounts.cashOnHand, Accounts.receivableStudents]),
      );
      expect(trial.rows.length, greaterThan(trial.posted.length));
    });

    test('rows read in the order a bookkeeper expects', () {
      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [
          entry(lines: [
            JournalLine.debit(Accounts.expenseUtilities, 'Utilities', 800),
            JournalLine.credit(Accounts.cashInBank, 'Cash in Bank', 800),
          ]),
          entry(lines: tuitionPayment(1500)),
        ],
      );

      final types = trial.posted.map((r) => r.account.type).toList();
      expect(types.first, AccountType.asset);
      expect(types.last, AccountType.expense);
    });

    test('an entry citing a code the chart has lost is still counted', () {
      // The case that matters: an account disappearing while entries
      // still cite it is how a trial balance stops balancing and nobody
      // can see why. It comes back under a placeholder so the total is
      // right and the problem is visible.
      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [
          entry(lines: [
            JournalLine.debit('9999', 'Something removed', 500),
            JournalLine.credit(Accounts.cashOnHand, 'Cash on Hand', 500),
          ]),
        ],
      );

      expect(trial.balances, isTrue);
      final orphan = trial.posted.firstWhere((r) => r.account.code == '9999');
      expect(orphan.account.name, 'Unknown account');
      expect(orphan.debits, 500);
    });

    test('surplus is revenue less expenses', () {
      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [
          entry(lines: [
            JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 10000),
            JournalLine.credit(Accounts.revenueTuition, 'Tuition Revenue', 10000),
          ]),
          entry(lines: [
            JournalLine.debit(Accounts.expenseSalaries, 'Salaries and Wages', 6000),
            JournalLine.credit(Accounts.cashInBank, 'Cash in Bank', 6000),
          ]),
        ],
      );

      expect(trial.totalFor(AccountType.revenue), 10000);
      expect(trial.totalFor(AccountType.expense), 6000);
      expect(trial.surplus, 4000);
    });
  });

  group('reversal', () {
    test('turns every debit into a credit and back', () {
      final original = entry(lines: tuitionPayment(1500));
      final reversed = original.reversedLines();

      expect(reversed, hasLength(2));
      expect(reversed.first.accountCode, Accounts.cashOnHand);
      expect(reversed.first.credit, 1500);
      expect(reversed.first.debit, 0);
      expect(reversed.last.debit, 1500);
      // And the reverse of a balanced entry is a balanced entry.
      expect(reasonEntryCannotPost(reversed), isNull);
    });

    test('an entry knows whether it has been reversed', () {
      expect(entry(lines: tuitionPayment(100)).isReversed, isFalse);
      expect(
        entry(lines: tuitionPayment(100), reversedBy: 'je_2').isReversed,
        isTrue,
      );
      expect(
        entry(lines: tuitionPayment(100), reversalOf: 'je_1').isReversal,
        isTrue,
      );
    });

    test('a reversal cancels the original out of the trial balance', () {
      final original = entry(id: 'a', lines: tuitionPayment(1500));
      final reversal = entry(
        id: 'b',
        lines: original.reversedLines(),
        source: EntrySource.reversal,
        reversalOf: 'a',
      );

      final trial = TrialBalance.from(
        chart: standardChartOfAccounts,
        entries: [original, reversal],
      );

      expect(trial.balances, isTrue);
      for (final row in trial.posted) {
        expect(sameMoney(row.balance, 0), isTrue,
            reason: '${row.account.label} should net to nothing');
      }
    });
  });

  group('the chart of accounts', () {
    test('every posting account the code references exists', () {
      // The constants are what the callables post to. One that is not in
      // the seeded chart is a journal entry that balances, posts, and
      // files the school's tuition under an account nobody can find.
      const posted = [
        Accounts.cashOnHand,
        Accounts.cashInBank,
        Accounts.eWallet,
        Accounts.receivableStudents,
        Accounts.payableTrade,
        Accounts.payableSss,
        Accounts.payablePhilHealth,
        Accounts.payablePagIbig,
        Accounts.payableWithholding,
        Accounts.fundBalance,
        Accounts.revenueTuition,
        Accounts.revenueMiscFees,
        Accounts.revenueOther,
        Accounts.expenseSalaries,
        Accounts.expenseBenefits,
        Accounts.expenseCashVariance,
        Accounts.expenseOther,
      ];
      final codes = standardChartOfAccounts.map((a) => a.code).toSet();

      for (final code in posted) {
        expect(codes, contains(code), reason: '$code is posted to but not seeded');
      }
    });

    test('every account the postings need is a system account', () {
      // System accounts cannot be deactivated. One that could be would
      // take the next payment down with it.
      final system = {
        for (final a in standardChartOfAccounts)
          if (a.isSystem) a.code,
      };
      expect(system, contains(Accounts.cashOnHand));
      expect(system, contains(Accounts.receivableStudents));
      expect(system, contains(Accounts.payableWithholding));
    });

    test('codes are unique', () {
      final codes = standardChartOfAccounts.map((a) => a.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('every code sits in the block its type owns', () {
      // Assets in the 1000s, liabilities in the 2000s. A school filing an
      // expense under 1500 gets its light bill on the balance sheet as an
      // asset, and finds out months later.
      const block = {
        AccountType.asset: '1',
        AccountType.liability: '2',
        AccountType.equity: '3',
        AccountType.revenue: '4',
        AccountType.expense: '5',
      };
      for (final account in standardChartOfAccounts) {
        expect(account.code, startsWith(block[account.type]!),
            reason: '${account.label} is a ${account.type.value}');
      }
    });
  });

  group('where a payment lands', () {
    test('each method goes to the cash account it really sits in', () {
      // An online payment is a bank deposit by the time the school sees
      // it; GCash sits in the wallet until it is cashed out. Getting this
      // wrong makes a bank reconciliation impossible.
      expect(cashAccountForMethod('cash'), Accounts.cashOnHand);
      expect(cashAccountForMethod('gcash'), Accounts.eWallet);
      expect(cashAccountForMethod('bank_transfer'), Accounts.cashInBank);
      expect(cashAccountForMethod('online'), Accounts.cashInBank);
    });

    test('an unknown method falls back to cash rather than throwing', () {
      // A method this build has not heard of must not take the payment
      // down with it. It lands somewhere real and visible.
      expect(cashAccountForMethod('crypto'), Accounts.cashOnHand);
    });

    test('each purpose is earned into its own revenue account', () {
      expect(revenueAccountForPurpose('tuition'), Accounts.revenueTuition);
      expect(revenueAccountForPurpose('misc_fee'), Accounts.revenueMiscFees);
      expect(revenueAccountForPurpose('other'), Accounts.revenueOther);
      expect(revenueAccountForPurpose('nonsense'), Accounts.revenueOther);
    });
  });
}
