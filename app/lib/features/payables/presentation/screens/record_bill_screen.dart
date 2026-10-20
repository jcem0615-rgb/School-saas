import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../budgets/presentation/controllers/budgets_controller.dart';
import '../../../ledger/domain/entities/ledger_account.dart';
import '../../../ledger/presentation/controllers/ledger_controller.dart'
    show chartOfAccountsProvider;
import '../../domain/entities/bill.dart';
import '../../domain/entities/vendor.dart';
import '../controllers/payables_controller.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat('d MMM y');

/// Entering a supplier's invoice.
///
/// The due date fills itself in from the supplier's terms the moment one
/// is chosen. A date somebody has to work out by hand is a date that
/// gets typed as today, and then every ageing report is wrong.
class RecordBillScreen extends ConsumerStatefulWidget {
  const RecordBillScreen({super.key});

  @override
  ConsumerState<RecordBillScreen> createState() => _RecordBillScreenState();
}

class _DraftLine {
  String? accountCode;
  final description = TextEditingController();
  final amount = TextEditingController();

  double get value => double.tryParse(amount.text.trim()) ?? 0;

  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

class _RecordBillScreenState extends ConsumerState<RecordBillScreen> {
  final _billNumber = TextEditingController();
  final _notes = TextEditingController();
  Vendor? _vendor;
  DateTime _billDate = DateTime.now();
  DateTime? _dueDate;
  final _lines = [_DraftLine()];

  @override
  void dispose() {
    _billNumber.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// The due date, unless somebody has overridden it.
  DateTime get _effectiveDueDate =>
      _dueDate ?? _vendor?.dueDateFor(_billDate) ?? _billDate;

  List<BillLine> _built(List<LedgerAccount> chart) {
    final byCode = {for (final a in chart) a.code: a};
    return [
      for (final line in _lines)
        if (line.accountCode != null && line.value > 0)
          BillLine(
            accountCode: line.accountCode!,
            accountName: byCode[line.accountCode]?.name ?? '',
            description: line.description.text.trim(),
            amount: line.value,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? const <Vendor>[];
    final chart = ref.watch(chartOfAccountsProvider).valueOrNull ?? const [];
    // Only things a bill can buy. Coding one to revenue balances and
    // means nothing, and nobody reading the expense report later could
    // tell why it was short.
    final buyable = chart
        .where((a) =>
            a.isActive &&
            (a.type == AccountType.expense || a.type == AccountType.asset))
        .toList();

    final lines = _built(chart);
    final total = lines.fold<double>(0, (sum, l) => sum + l.amount);
    final problem = reasonBillCannotBeRecorded(
      vendorId: _vendor?.id ?? '',
      billNumber: _billNumber.text,
      billDate: _billDate,
      dueDate: _effectiveDueDate,
      lines: lines,
    );
    final working = ref.watch(payablesActionControllerProvider).isLoading;

    ref.listen(payablesActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Enter a bill')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Vendor>(
            isExpanded: true,
            initialValue: _vendor,
            decoration: const InputDecoration(
              labelText: 'Supplier',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final vendor in vendors.where((v) => v.isActive))
                DropdownMenuItem(
                  value: vendor,
                  child: Text('${vendor.name}  ·  ${vendor.termsLabel}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _vendor = v;
              // Recomputed from the new supplier's terms unless somebody
              // has already overridden it by hand.
              _dueDate = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _billNumber,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: "The number on the supplier's invoice",
              hintText: 'SI-99321',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _billDate,
                      firstDate: DateTime(DateTime.now().year - 2),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _billDate = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Dated ${_dateFormat.format(_billDate)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _effectiveDueDate,
                      firstDate: _billDate,
                      lastDate: DateTime(DateTime.now().year + 2),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text('Due ${_dateFormat.format(_effectiveDueDate)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('What it is for', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, line) in _lines.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: line.accountCode,
                    decoration: const InputDecoration(
                      labelText: 'Account',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final account in buyable)
                        DropdownMenuItem(
                          value: account.code,
                          child: Text(account.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => line.accountCode = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: line.description,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: line.amount,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (_lines.length > 1)
                        IconButton(
                          tooltip: 'Remove line',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _lines.removeAt(index).dispose()),
                        ),
                    ],
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
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const Divider(height: 32),
          Text('Total ${_money.format(total)}', style: theme.textTheme.titleLarge),
          // A budget warns, it never refuses. A school that cannot
          // record the electricity bill because somebody budgeted too
          // little does not thereby spend less -- it just has a
          // liability nobody can see, which is worse than an overspend
          // somebody can.
          for (final warning in _budgetWarnings(ref, lines))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: working || problem != null ? null : () => _record(chart),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Record the bill'),
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

  /// What this bill would do to the plan, one line per account.
  ///
  /// Amounts are summed per account first: two lines coded to Supplies
  /// breach together or not at all, and warning twice about the same
  /// account reads as two separate problems.
  List<String> _budgetWarnings(WidgetRef ref, List<BillLine> lines) {
    final report = ref.watch(budgetReportProvider);
    if (report == null) return const [];
    final byAccount = <String, double>{};
    for (final line in lines) {
      byAccount[line.accountCode] = (byAccount[line.accountCode] ?? 0) + line.amount;
    }
    return [
      for (final entry in byAccount.entries)
        if (budgetWarningFor(
              report: report,
              accountCode: entry.key,
              amount: entry.value,
            )
            case final String warning)
          warning,
    ];
  }

  Future<void> _record(List<LedgerAccount> chart) async {
    final ok = await ref.read(payablesActionControllerProvider.notifier).recordBill(
          vendorId: _vendor!.id,
          billNumber: _billNumber.text,
          billDate: _billDate,
          dueDate: _effectiveDueDate,
          lines: _built(chart),
          notes: _notes.text,
        );
    if (!mounted || !ok) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Bill recorded.')));
  }
}
