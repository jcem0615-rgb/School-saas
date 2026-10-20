import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';
import '../controllers/ledger_controller.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat('d MMM y');

/// An entry somebody writes.
///
/// Opening balances, a correction an auditor asked for. Everything with
/// an event behind it is posted by that event, so this screen is the
/// exception and the running difference at the bottom is the whole of
/// its design: an entry that does not balance cannot be posted, and the
/// person should be able to see that before they try.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _DraftLine {
  String? accountCode;
  bool isDebit = true;
  final controller = TextEditingController();

  double get amount => double.tryParse(controller.text.trim()) ?? 0;
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _memoController = TextEditingController();
  DateTime _date = DateTime.now();
  // Two to start with, because an entry of one line is not an entry and
  // starting at one invites somebody to try.
  final _lines = [_DraftLine(), _DraftLine()];

  @override
  void dispose() {
    _memoController.dispose();
    for (final line in _lines) {
      line.controller.dispose();
    }
    super.dispose();
  }

  List<JournalLine> _built(List<LedgerAccount> chart) {
    final byCode = {for (final a in chart) a.code: a};
    return [
      for (final line in _lines)
        if (line.accountCode != null && line.amount > 0)
          JournalLine(
            accountCode: line.accountCode!,
            accountName: byCode[line.accountCode]?.name ?? '',
            debit: line.isDebit ? line.amount : 0,
            credit: line.isDebit ? 0 : line.amount,
          ),
    ];
  }

  Future<void> _post(List<LedgerAccount> chart) async {
    final lines = _built(chart);
    final number = await ref.read(ledgerActionControllerProvider.notifier).postManualEntry(
          date: _date,
          memo: _memoController.text,
          lines: lines,
        );
    if (!mounted || number == null) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Posted as $number.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chart = ref.watch(chartOfAccountsProvider).valueOrNull ?? const [];
    final usable = chart.where((a) => a.isActive).toList();
    final lines = _built(chart);
    final debits = lines.fold<double>(0, (sum, l) => sum + l.debit);
    final credits = lines.fold<double>(0, (sum, l) => sum + l.credit);
    final difference = debits - credits;
    final problem = reasonEntryCannotPost(lines);
    final working = ref.watch(ledgerActionControllerProvider).isLoading;

    ref.listen(ledgerActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('New journal entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _memoController,
            decoration: const InputDecoration(
              labelText: 'What this entry is for',
              hintText: 'Opening balances as at 1 June',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(DateTime.now().year - 4),
                // Never the future: an entry dated forward is almost
                // always a mistyped year, and it lands outside every
                // period anyone will look at.
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(_dateFormat.format(_date)),
          ),
          const SizedBox(height: 20),
          Text('Lines', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, line) in _lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: line.accountCode,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final account in usable)
                          DropdownMenuItem(
                            value: account.code,
                            child: Text(account.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) => setState(() => line.accountCode = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Dr')),
                        ButtonSegment(value: false, label: Text('Cr')),
                      ],
                      selected: {line.isDebit},
                      onSelectionChanged: (s) =>
                          setState(() => line.isDebit = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: line.controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_lines.length > 2)
                    IconButton(
                      tooltip: 'Remove line',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _lines.removeAt(index).controller.dispose();
                      }),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lines.add(_DraftLine())),
              icon: const Icon(Icons.add),
              label: const Text('Add a line'),
            ),
          ),
          const Divider(height: 32),
          // The running difference. Shown always, because the one thing
          // somebody needs to know while typing is how far out they are.
          Row(
            children: [
              Expanded(
                child: Text('Debits ${_money.format(debits)}',
                    style: theme.textTheme.titleSmall),
              ),
              Expanded(
                child: Text('Credits ${_money.format(credits)}',
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sameMoney(difference, 0)
                ? 'Balanced.'
                : 'Out by ${_money.format(difference.abs())} '
                    '(${difference > 0 ? 'more debit' : 'more credit'}).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: sameMoney(difference, 0)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: working || problem != null ? null : () => _post(chart),
            icon: const Icon(Icons.post_add_outlined),
            label: const Text('Post entry'),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(problem, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
