import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../controllers/ledger_controller.dart';
import 'manual_entry_screen.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat('d MMM y');

/// The books.
///
/// Three views of one thing, which is why they are tabs rather than three
/// screens: the trial balance is the journal added up, and the chart is
/// the list of buckets both of them use.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(ledgerPeriodProvider);

    ref.listen(ledgerActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) _say('$error');
    });

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('General Ledger'),
          actions: [
            TextButton.icon(
              onPressed: _pickPeriod,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(period.label),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Trial Balance'),
            Tab(text: 'Journal'),
            Tab(text: 'Accounts'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
          ),
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('New entry'),
        ),
        body: const TabBarView(children: [
          _TrialBalanceTab(),
          _JournalTab(),
          _ChartTab(),
        ]),
      ),
    );
  }

  /// Which school year the books are read over.
  ///
  /// A school year, not a calendar one: June to March is the period a
  /// school reports on, and a ledger that defaulted to January would
  /// split every year it is asked about in half.
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final years = [for (var i = 0; i < 4; i++) now.year - i];
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('School year'),
        children: [
          for (final year in years)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(year),
              child: Text('$year-${year + 1}'),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    ref.read(ledgerPeriodProvider.notifier).state =
        LedgerPeriod.schoolYear(chosen);
  }
}

class _TrialBalanceTab extends ConsumerWidget {
  const _TrialBalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trial = ref.watch(trialBalanceProvider);

    if (trial == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = trial.posted;
    if (rows.isEmpty) {
      return const _Message(
        icon: Icons.account_balance_outlined,
        title: 'Nothing posted yet',
        detail: 'Fees assessed, payments collected and payroll runs post '
            'here on their own. Nothing has to be typed up.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        // The one line an accountant looks at first, so it is the first
        // line on the page.
        Container(
          color: trial.balances
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.errorContainer,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                trial.balances ? Icons.check_circle_outline : Icons.error_outline,
                color: trial.balances ? null : theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trial.balances
                      ? 'The books balance. ${_money.format(trial.totalDebits)} '
                          'on each side.'
                      : 'Out by ${_money.format(
                          (trial.totalDebits - trial.totalCredits).abs(),
                        )}. Something has been posted that should not have been.',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        for (final type in AccountType.values)
          if (rows.any((r) => r.account.type == type)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(type.groupLabel, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    _money.format(trial.totalFor(type)),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final row in rows.where((r) => r.account.type == type))
              ListTile(
                dense: true,
                title: Text(row.account.label),
                subtitle: Text(
                  'Dr ${_money.format(row.debits)}   '
                  'Cr ${_money.format(row.credits)}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Text(
                  _money.format(row.balance),
                  style: theme.textTheme.titleSmall,
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _AccountLedgerScreen(account: row.account),
                )),
              ),
          ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Surplus for the period: ${_money.format(trial.surplus)}',
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _JournalTab extends ConsumerWidget {
  const _JournalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(journalProvider);

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: Icons.error_outline,
        title: 'The journal could not be read',
        detail: '$e',
      ),
      data: (entries) => entries.isEmpty
          ? const _Message(
              icon: Icons.receipt_long_outlined,
              title: 'No entries in this period',
              detail: 'Try another school year.',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _EntryTile(entry: entries[i]),
            ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final JournalEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.memo,
              style: TextStyle(
                decoration: entry.isReversed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(_money.format(entry.amount), style: theme.textTheme.titleSmall),
        ],
      ),
      subtitle: Text(
        '${entry.entryNumber} · ${_dateFormat.format(entry.date)} · '
        '${entry.source.displayLabel}'
        '${entry.isReversed ? ' · reversed' : ''}',
        style: muted,
      ),
      children: [
        for (final line in entry.lines)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${line.accountCode} - ${line.accountName}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    line.debit > 0 ? _money.format(line.debit) : '',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    line.credit > 0 ? _money.format(line.credit) : '',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text('Posted by ${entry.postedByName}', style: muted),
              ),
              // A reversal is the only correction there is, and an entry
              // that has already been reversed has nothing left to undo.
              if (!entry.isReversed && !entry.isReversal)
                TextButton.icon(
                  onPressed: () => _reverse(context, ref),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Reverse'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _reverse(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reverse ${entry.entryNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The opposite entry is posted today. Nothing is deleted and '
              'nothing is edited — both stay in the journal.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Why',
                hintText: 'Posted against the wrong account',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;

    final number = await ref
        .read(ledgerActionControllerProvider.notifier)
        .reverseEntry(entry: entry, reason: reason);
    if (number != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Reversed as $number.')));
    }
  }
}

class _ChartTab extends ConsumerWidget {
  const _ChartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chartAsync = ref.watch(chartOfAccountsProvider);

    return chartAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: Icons.error_outline,
        title: 'The chart could not be read',
        detail: '$e',
      ),
      data: (accounts) => ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final type in AccountType.values)
            if (accounts.any((a) => a.type == type)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                child: Text(type.groupLabel, style: theme.textTheme.titleMedium),
              ),
              const Divider(height: 1),
              for (final account in accounts.where((a) => a.type == type))
                ListTile(
                  dense: true,
                  title: Text(account.label),
                  subtitle: account.description == null
                      ? null
                      : Text(account.description!),
                  trailing: account.isActive
                      ? Text(account.type.normalBalance,
                          style: theme.textTheme.bodySmall)
                      : const Chip(label: Text('Not in use')),
                ),
            ],
        ],
      ),
    );
  }
}

/// Every entry that touched one account, for drilling into a trial
/// balance figure that looks wrong.
class _AccountLedgerScreen extends ConsumerWidget {
  final LedgerAccount account;
  const _AccountLedgerScreen({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(accountLedgerProvider(account.code));

    return Scaffold(
      appBar: AppBar(title: Text(account.label)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not be read',
          detail: '$e',
        ),
        data: (entries) {
          // A running balance, oldest first, which is the only order a
          // running balance means anything in.
          final oldestFirst = entries.reversed.toList();
          var running = 0.0;
          final rows = <Widget>[];
          for (final entry in oldestFirst) {
            for (final line in entry.lines.where((l) => l.accountCode == account.code)) {
              running += account.type.increasesOnDebit
                  ? line.debit - line.credit
                  : line.credit - line.debit;
              rows.add(ListTile(
                dense: true,
                title: Text(entry.memo),
                subtitle: Text(
                  '${entry.entryNumber} · ${_dateFormat.format(entry.date)}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      line.isDebit
                          ? 'Dr ${_money.format(line.debit)}'
                          : 'Cr ${_money.format(line.credit)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(_money.format(running), style: theme.textTheme.titleSmall),
                  ],
                ),
              ));
            }
          }
          if (rows.isEmpty) {
            return const _Message(
              icon: Icons.inbox_outlined,
              title: 'Nothing posted to this account',
              detail: 'In this school year, at least.',
            );
          }
          return ListView(children: rows.reversed.toList());
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _Message({required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(detail, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
