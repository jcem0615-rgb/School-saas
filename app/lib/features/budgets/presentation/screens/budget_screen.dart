import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../ledger/domain/entities/ledger_account.dart';
import '../../../ledger/presentation/controllers/ledger_controller.dart'
    show chartOfAccountsProvider, ledgerPeriodProvider;
import '../../../ledger/domain/repositories/ledger_repository.dart';
import '../../domain/entities/budget.dart';
import '../controllers/budgets_controller.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _percent = NumberFormat.percentPattern();

/// The plan, next to what actually happened.
///
/// What needs attention is at the top, because a report ordered by
/// account code makes somebody read all of it to find the one line that
/// matters. Everything else is underneath, grouped the way the chart is.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(budgetReportProvider);
    final year = ref.watch(budgetYearProvider);
    final working = ref.watch(budgetsActionControllerProvider).isLoading;

    ref.listen(budgetsActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          TextButton.icon(
            onPressed: () => _pickYear(context, ref),
            icon: const Icon(Icons.date_range_outlined),
            label: Text(year),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: working ? null : () => _setBudget(context, ref),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Set a budget'),
      ),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : report.isEmpty
              ? const _Message(
                  icon: Icons.savings_outlined,
                  title: 'Nothing budgeted for this year',
                  detail: 'Set an allowance against an account and what is '
                      'spent against it will show up here on its own.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (working) const LinearProgressIndicator(minHeight: 2),
                    _SurplusCard(report: report),
                    if (report.needingAttention.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('Needs attention',
                            style: theme.textTheme.titleMedium),
                      ),
                      const Divider(height: 1),
                      for (final line in report.needingAttention)
                        _BudgetTile(
                          line: line,
                          onTap: () => _setBudget(context, ref, line: line),
                        ),
                    ],
                    for (final type in [AccountType.expense, AccountType.revenue])
                      if (report.forType(type).isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(type.groupLabel,
                                    style: theme.textTheme.titleMedium),
                              ),
                              Text(
                                '${_money.format(report.actualFor(type))} of '
                                '${_money.format(report.budgetedFor(type))}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        for (final line in report.forType(type))
                          _BudgetTile(
                            line: line,
                            onTap: () => _setBudget(context, ref, line: line),
                          ),
                      ],
                  ],
                ),
    );
  }

  Future<void> _pickYear(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final years = [for (var i = 0; i < 4; i++) now.year - i];
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('School year'),
        children: [
          for (final year in years)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(year),
              child: Text('$year-${year + 1}'),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    // The ledger's period, so the plan and the books are never looking
    // at different years.
    ref.read(ledgerPeriodProvider.notifier).state = LedgerPeriod.schoolYear(chosen);
  }

  Future<void> _setBudget(
    BuildContext context,
    WidgetRef ref, {
    BudgetLine? line,
  }) async {
    final chart = ref.read(chartOfAccountsProvider).valueOrNull ?? const [];
    final result = await showDialog<({String code, double amount, String? note})>(
      context: context,
      builder: (_) => _SetBudgetDialog(chart: chart, line: line),
    );
    if (result == null || !context.mounted) return;

    final ok = await ref.read(budgetsActionControllerProvider.notifier).setBudget(
          accountCode: result.code,
          amount: result.amount,
          note: result.note,
        );
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Budget set.')));
    }
  }
}

class _SurplusCard extends StatelessWidget {
  final BudgetReport report;
  const _SurplusCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ahead = report.actualSurplus >= report.plannedSurplus;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${report.schoolYear} so far', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_money.format(report.actualSurplus),
                style: theme.textTheme.headlineMedium),
            Text(
              'Planned ${_money.format(report.plannedSurplus)} '
              '— ${ahead ? 'ahead of' : 'behind'} the plan',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ahead ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  final BudgetLine line;
  final VoidCallback onTap;
  const _BudgetTile({required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = switch (line.state) {
      BudgetState.over => theme.colorScheme.error,
      BudgetState.unbudgeted => theme.colorScheme.tertiary,
      BudgetState.near => theme.colorScheme.secondary,
      BudgetState.within => theme.colorScheme.primary,
    };
    final used = line.usedFraction;

    return ListTile(
      onTap: onTap,
      title: Text('${line.accountCode} - ${line.accountName}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (used != null)
            // Clamped only for the bar: the numbers underneath still say
            // how far over it went.
            LinearProgressIndicator(
              value: used.clamp(0.0, 1.0),
              color: colour,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          const SizedBox(height: 4),
          Text(
            line.isBudgeted
                ? '${_money.format(line.actual)} of ${_money.format(line.budgeted)}'
                    ' · ${_percent.format(used)} · ${line.state.displayLabel}'
                : '${_money.format(line.actual)} spent · ${line.state.displayLabel}',
            style: theme.textTheme.bodySmall?.copyWith(color: colour),
          ),
          if (line.note != null)
            Text(line.note!, style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: true,
      trailing: Text(
        line.isBudgeted ? _money.format(line.remaining) : '—',
        style: theme.textTheme.titleSmall?.copyWith(
          color: line.remaining < 0 ? theme.colorScheme.error : null,
        ),
      ),
    );
  }
}

class _SetBudgetDialog extends StatefulWidget {
  final List<LedgerAccount> chart;
  final BudgetLine? line;
  const _SetBudgetDialog({required this.chart, this.line});

  @override
  State<_SetBudgetDialog> createState() => _SetBudgetDialogState();
}

class _SetBudgetDialogState extends State<_SetBudgetDialog> {
  late String? _code = widget.line?.accountCode;
  late final _amount = TextEditingController(
    text: widget.line?.budgeted == null || widget.line!.budgeted == 0
        ? ''
        : widget.line!.budgeted.toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.line?.note ?? '');

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only spending and income. A school does not budget its bank
    // balance, and the report would not know what to do with one.
    final budgetable = widget.chart
        .where((a) =>
            a.isActive &&
            (a.type == AccountType.expense || a.type == AccountType.revenue))
        .toList();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final account = budgetable.where((a) => a.code == _code).firstOrNull;
    final problem = reasonBudgetCannotBeSet(
      schoolYear: 'set',
      account: account,
      amount: amount,
    );

    return AlertDialog(
      title: const Text('Set a budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _code,
            decoration: const InputDecoration(
              labelText: 'Account',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in budgetable)
                DropdownMenuItem(
                  value: a.code,
                  child: Text(a.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _code = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Allowance for the year',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Meralco and Maynilad',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Setting it to zero takes the line off the plan. Anything '
            'spent against it still shows, as unbudgeted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (problem != null && account != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop((
                  code: _code!,
                  amount: amount,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                )),
          child: const Text('Save'),
        ),
      ],
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
