import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/ledger/domain/entities/journal_entry.dart';
import 'package:logicclass/features/ledger/domain/entities/ledger_account.dart';
import 'package:logicclass/features/ledger/domain/repositories/ledger_repository.dart';
import 'package:logicclass/features/ledger/presentation/controllers/ledger_controller.dart';
import 'package:logicclass/features/ledger/presentation/screens/ledger_screen.dart';

/// The books, end to end on the demo repositories.
///
/// The property under test throughout is the one an accountant checks
/// first: the trial balance adds up. Everything else here exists to keep
/// it true -- entries that do not balance are refused, and nothing is
/// ever edited.
void main() {
  /// Refusals are collected as they happen rather than read back off the
  /// controller afterwards: it is autoDispose, and the demo repositories
  /// watch authStateProvider, so an auth emission can rebuild it and
  /// take the error state with it.
  final refusals = <String>[];

  Future<ProviderContainer> signedInDirector() async {
    refusals.clear();
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
        );
    // Sign-in has to settle before the controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(ledgerActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) refusals.add('$error');
    });
    addTearDown(sub.close);
    return container;
  }

  /// The whole journal, not just the current period: the seeded entries
  /// are spread over a term and the default period would hide some.
  TrialBalance trialOf(ProviderContainer c) {
    final store = c.read(demoStoreProvider);
    return TrialBalance.from(
      chart: store.ledgerAccounts.value,
      entries: store.journalEntries.value,
    );
  }

  group('the seeded books', () {
    test('balance', () async {
      // A demo whose trial balance is out is a demo that argues against
      // the feature.
      final c = await signedInDirector();
      final trial = trialOf(c);

      expect(trial.balances, isTrue,
          reason: 'out by ${trial.totalDebits - trial.totalCredits}');
      expect(trial.totalDebits, greaterThan(0));
    });

    test('are posted by events, not typed by anybody', () async {
      // Almost nothing in a real school's ledger should be hand-written,
      // and a demo seeded with manual entries would teach the opposite.
      final c = await signedInDirector();
      final entries = c.read(demoStoreProvider).journalEntries.value;

      expect(entries, isNotEmpty);
      expect(
        entries.where((e) => e.source.isHandWritten),
        isEmpty,
        reason: 'every seeded entry should come from an event',
      );
    });

    test('every entry in them balances on its own', () async {
      final c = await signedInDirector();
      for (final entry in c.read(demoStoreProvider).journalEntries.value) {
        expect(reasonEntryCannotPost(entry.lines), isNull,
            reason: '${entry.entryNumber} does not balance');
      }
    });

    test('cite only accounts the chart has', () async {
      // An entry citing a code the chart has lost is the thing that makes
      // a trial balance stop balancing in a way nobody can see.
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final codes = store.ledgerAccounts.value.map((a) => a.code).toSet();

      for (final entry in store.journalEntries.value) {
        for (final line in entry.lines) {
          expect(codes, contains(line.accountCode),
              reason: '${entry.entryNumber} cites ${line.accountCode}');
        }
      }
    });
  });

  group('posting by hand', () {
    test('an entry that balances is accepted', () async {
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final before = store.journalEntries.value.length;

      final number = await c.read(ledgerActionControllerProvider.notifier).postManualEntry(
            date: DateTime.now(),
            memo: 'Opening balance correction',
            lines: [
              JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 5000),
              JournalLine.credit(Accounts.fundBalance, 'Fund Balance', 5000),
            ],
          );

      expect(number, isNotNull);
      expect(number, startsWith('JE-'));
      expect(store.journalEntries.value, hasLength(before + 1));
      expect(store.journalEntries.value.first.source, EntrySource.manual);
      // Still balanced afterwards, which is the only thing that matters.
      expect(trialOf(c).balances, isTrue);
    });

    test('one that does not balance is refused, with the difference', () async {
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final before = store.journalEntries.value.length;

      final number = await c.read(ledgerActionControllerProvider.notifier).postManualEntry(
            date: DateTime.now(),
            memo: 'Wrong on purpose',
            lines: [
              JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 5000),
              JournalLine.credit(Accounts.fundBalance, 'Fund Balance', 4000),
            ],
          );

      expect(number, isNull);
      expect(store.journalEntries.value, hasLength(before));
      // Said in pesos, because "this entry is invalid" is not worth
      // saying to somebody who has just typed twelve numbers.
      expect(refusals.last, contains('1000.00'));
    });

    test('an entry with no explanation is refused', () async {
      // The one thing an auditor will ask about, and the one thing
      // nobody will remember.
      final c = await signedInDirector();
      final number = await c.read(ledgerActionControllerProvider.notifier).postManualEntry(
            date: DateTime.now(),
            memo: '  ',
            lines: [
              JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 100),
              JournalLine.credit(Accounts.fundBalance, 'Fund Balance', 100),
            ],
          );
      expect(number, isNull);
    });

    test('an entry dated in the future is refused', () async {
      final c = await signedInDirector();
      final number = await c.read(ledgerActionControllerProvider.notifier).postManualEntry(
            date: DateTime.now().add(const Duration(days: 30)),
            memo: 'Next month, somehow',
            lines: [
              JournalLine.debit(Accounts.cashOnHand, 'Cash on Hand', 100),
              JournalLine.credit(Accounts.fundBalance, 'Fund Balance', 100),
            ],
          );
      expect(number, isNull);
    });

    test('an account the chart does not have is refused', () async {
      final c = await signedInDirector();
      final number = await c.read(ledgerActionControllerProvider.notifier).postManualEntry(
            date: DateTime.now(),
            memo: 'Into thin air',
            lines: [
              JournalLine.debit('7777', 'Nowhere', 100),
              JournalLine.credit(Accounts.fundBalance, 'Fund Balance', 100),
            ],
          );
      expect(number, isNull);
    });
  });

  group('correcting', () {
    test('a reversal cancels the entry out and leaves both on the record',
        () async {
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final target = store.journalEntries.value
          .firstWhere((e) => e.source == EntrySource.expense);
      final before = store.journalEntries.value.length;

      final number = await c.read(ledgerActionControllerProvider.notifier).reverseEntry(
            entry: target,
            reason: 'Posted against the wrong account',
          );

      expect(number, isNotNull);
      // Both are there. Nothing was deleted and nothing was edited apart
      // from the back-reference.
      expect(store.journalEntries.value, hasLength(before + 1));
      final original =
          store.journalEntries.value.firstWhere((e) => e.id == target.id);
      expect(original.isReversed, isTrue);
      expect(original.lines, hasLength(target.lines.length));

      final reversal =
          store.journalEntries.value.firstWhere((e) => e.reversalOf == target.id);
      expect(reversal.source, EntrySource.reversal);
      expect(reversal.memo, contains(target.entryNumber));

      // And the two net to nothing.
      final trial = TrialBalance.from(
        chart: store.ledgerAccounts.value,
        entries: [original, reversal],
      );
      for (final row in trial.posted) {
        expect(sameMoney(row.balance, 0), isTrue);
      }
      expect(trialOf(c).balances, isTrue);
    });

    test('reversing the same entry twice is refused', () async {
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final target = store.journalEntries.value
          .firstWhere((e) => e.source == EntrySource.payroll);
      final controller = c.read(ledgerActionControllerProvider.notifier);

      expect(await controller.reverseEntry(entry: target, reason: 'A mistake'),
          isNotNull);

      final again = store.journalEntries.value.firstWhere((e) => e.id == target.id);
      expect(await controller.reverseEntry(entry: again, reason: 'Again'), isNull);
    });

    test('a reversal cannot itself be reversed', () async {
      // That is how a journal turns into a tangle nobody can read.
      final c = await signedInDirector();
      final store = c.read(demoStoreProvider);
      final target = store.journalEntries.value
          .firstWhere((e) => e.source == EntrySource.assessment);
      final controller = c.read(ledgerActionControllerProvider.notifier);

      await controller.reverseEntry(entry: target, reason: 'A mistake');
      final reversal =
          store.journalEntries.value.firstWhere((e) => e.reversalOf == target.id);

      expect(await controller.reverseEntry(entry: reversal, reason: 'Undo'), isNull);
    });
  });

  group('the chart', () {
    test('a new account has to sit in the block its type owns', () async {
      final c = await signedInDirector();
      final controller = c.read(ledgerActionControllerProvider.notifier);
      final chart = c.read(demoStoreProvider).ledgerAccounts.value;

      expect(
        await controller.addAccount(
          code: '1500',
          name: 'Transport',
          type: AccountType.expense,
          existing: chart,
        ),
        isFalse,
        reason: 'an expense filed in the 1000s lands on the balance sheet',
      );
      expect(
        await controller.addAccount(
          code: '5400',
          name: 'Transport',
          type: AccountType.expense,
          existing: chart,
        ),
        isTrue,
      );
    });

    test('a system account cannot be switched off', () async {
      // The automatic postings find it by code. One that could be
      // deactivated would take the next payment down with it.
      final c = await signedInDirector();
      final cash = c
          .read(demoStoreProvider)
          .ledgerAccounts
          .value
          .firstWhere((a) => a.code == Accounts.cashOnHand);

      expect(
        await c
            .read(ledgerActionControllerProvider.notifier)
            .updateAccount(account: cash, isActive: false),
        isFalse,
      );
      // ...but it can be renamed.
      expect(
        await c
            .read(ledgerActionControllerProvider.notifier)
            .updateAccount(account: cash, name: 'Cash at the window'),
        isTrue,
      );
    });
  });

  group('the screen', () {
    testWidgets('opens on a trial balance that says it balances',
        (tester) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await signedInDirector();
        // The seeded entries are spread over a term, so read them over a
        // period wide enough to hold all of them.
        c.read(ledgerPeriodProvider.notifier).state = LedgerPeriod(
          from: DateTime.now().subtract(const Duration(days: 365)),
          to: DateTime.now(),
          label: 'All',
        );
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: LedgerScreen()),
        ),
      );
      // Pumped rather than settled: the loading state is a
      // CircularProgressIndicator, which animates for ever, so
      // pumpAndSettle here waits for something that never stops. The
      // real wait is the demo repositories' latency, and that has to
      // happen on the real clock inside runAsync.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Trial Balance'), findsOneWidget);
      expect(find.textContaining('The books balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
