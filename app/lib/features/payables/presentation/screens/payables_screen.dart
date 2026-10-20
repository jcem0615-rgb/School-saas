import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../ledger/domain/entities/ledger_account.dart';
import '../../domain/entities/bill.dart';
import '../controllers/payables_controller.dart';
import 'record_bill_screen.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat('d MMM y');

/// What the school owes.
///
/// The ageing report is first, not the list of bills, because the
/// question a director opens this with is "how far behind are we" and
/// the answer is four numbers. The bills underneath are what to do about
/// it, in the order they fall due.
class PayablesScreen extends ConsumerStatefulWidget {
  const PayablesScreen({super.key});

  @override
  ConsumerState<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends ConsumerState<PayablesScreen> {
  /// Settled bills are off the list until asked for. They are history,
  /// and the list exists to answer what is still owed.
  bool _showSettled = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billsAsync = ref.watch(billsProvider);
    final ageing = ref.watch(payablesAgeingProvider);
    final working = ref.watch(payablesActionControllerProvider).isLoading;

    ref.listen(payablesActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) _say('$error');
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts Payable')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: working
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordBillScreen()),
                ),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Enter a bill'),
      ),
      body: billsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'The payables ledger could not be read',
          detail: '$e',
        ),
        data: (bills) {
          final shown = (_showSettled ? bills : bills.where((b) => b.isOutstanding))
              .toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (working) const LinearProgressIndicator(minHeight: 2),
              _AgeingCard(ageing: ageing),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _showSettled ? 'Every bill' : 'Still owed',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _showSettled = !_showSettled),
                      icon: Icon(_showSettled
                          ? Icons.filter_alt_outlined
                          : Icons.history_outlined),
                      label: Text(_showSettled ? 'Only what is owed' : 'Show settled'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: _Message(
                    icon: Icons.check_circle_outline,
                    title: 'Nothing outstanding',
                    detail: 'Every bill on the ledger has been settled.',
                  ),
                )
              else
                for (final bill in shown)
                  _BillTile(
                    bill: bill,
                    onPay: working ? null : () => _pay(bill),
                    onVoid: working ? null : () => _void(bill),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pay(Bill bill) async {
    final result = await showDialog<({double amount, String account, String? reference})>(
      context: context,
      builder: (_) => _PayBillDialog(bill: bill),
    );
    if (result == null || !mounted) return;

    final ok = await ref.read(payablesActionControllerProvider.notifier).payBill(
          bill: bill,
          amount: result.amount,
          paidFromAccountCode: result.account,
          reference: result.reference,
        );
    if (ok && mounted) _say('Paid.');
  }

  Future<void> _void(Bill bill) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Void ${bill.billNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The bill stays on the ledger, marked void, and the amount '
              'owed is reversed in the books. Nothing is deleted.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Why',
                hintText: 'Duplicate of SI-99320',
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
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    final ok = await ref
        .read(payablesActionControllerProvider.notifier)
        .voidBill(bill: bill, reason: reason);
    if (ok && mounted) _say('Voided.');
  }
}

class _AgeingCard extends StatelessWidget {
  final PayablesAgeing ageing;
  const _AgeingCard({required this.ageing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (ageing.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: _Message(
          icon: Icons.check_circle_outline,
          title: 'The school owes nothing',
          detail: 'No bill on the ledger is outstanding.',
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Owed as at ${_dateFormat.format(ageing.asOf)}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _money.format(ageing.total),
              style: theme.textTheme.headlineMedium,
            ),
            if (ageing.overdue > 0)
              Text(
                '${_money.format(ageing.overdue)} of it is past due',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 16),
            for (final bucket in AgeingBucket.values)
              if ((ageing.totals[bucket] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(bucket.displayLabel)),
                      Text(
                        _money.format(ageing.totals[bucket]),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
            if (ageing.byVendor.length > 1) ...[
              const Divider(height: 24),
              Text('By supplier', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final entry in ageing.byVendor.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text(_money.format(
                        entry.value.values.fold<double>(0, (s, v) => s + v),
                      )),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback? onPay;
  final VoidCallback? onVoid;

  const _BillTile({required this.bill, required this.onPay, required this.onVoid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final overdueDays = bill.daysOverdueOn(DateTime.now());
    final late = bill.isOverdueOn(DateTime.now());

    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              bill.vendorName,
              style: TextStyle(
                decoration: bill.isVoid ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            _money.format(bill.isOutstanding ? bill.outstanding : bill.total),
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
      subtitle: Text(
        '${bill.billNumber} · ${bill.effectiveStatus.displayLabel}'
        '${late ? ' · $overdueDays days late' : ''}'
        '${bill.isOutstanding && !late ? ' · due ${_dateFormat.format(bill.dueDate)}' : ''}',
        style: late ? muted?.copyWith(color: theme.colorScheme.error) : muted,
      ),
      children: [
        for (final line in bill.lines)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('${line.description}  (${line.accountCode})',
                      style: theme.textTheme.bodySmall),
                ),
                Text(_money.format(line.amount), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        if (bill.payments.isNotEmpty) ...[
          const Divider(height: 16, indent: 24, endIndent: 16),
          for (final payment in bill.payments)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 16, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paid ${_dateFormat.format(payment.date)}'
                      '${payment.reference == null ? '' : ' · ${payment.reference}'}',
                      style: muted,
                    ),
                  ),
                  Text(_money.format(payment.amount), style: muted),
                ],
              ),
            ),
        ],
        if (bill.isVoid)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
            child: Text(
              'Voided by ${bill.voidedByName ?? 'the office'} — '
              '${bill.voidReason ?? 'no reason recorded'}',
              style: muted?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text('Entered by ${bill.recordedByName}', style: muted),
              ),
              if (bill.isOutstanding) ...[
                // Voiding is only offered while nothing has been paid.
                // After that the cash really did leave, and the bill has
                // to be settled or credited rather than vanished.
                if (bill.amountPaid == 0)
                  TextButton(onPressed: onVoid, child: const Text('Void')),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: onPay, child: const Text('Pay')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PayBillDialog extends StatefulWidget {
  final Bill bill;
  const _PayBillDialog({required this.bill});

  @override
  State<_PayBillDialog> createState() => _PayBillDialogState();
}

class _PayBillDialogState extends State<_PayBillDialog> {
  late final TextEditingController _amount =
      // Filled with what is left, because paying a bill off in full is
      // what happens nine times out of ten and retyping the figure is
      // how a digit gets dropped.
      TextEditingController(text: widget.bill.outstanding.toStringAsFixed(2));
  final _reference = TextEditingController();
  String _account = Accounts.cashInBank;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final problem = reasonPaymentCannotBeMade(
      bill: widget.bill,
      amount: amount,
      paidFromAccountCode: _account,
    );

    return AlertDialog(
      title: Text('Pay ${widget.bill.vendorName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_money.format(widget.bill.outstanding)} still owed on '
              '${widget.bill.billNumber}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _account,
            decoration: const InputDecoration(
              labelText: 'Paid from',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: Accounts.cashInBank, child: Text('Cash in Bank')),
              DropdownMenuItem(value: Accounts.cashOnHand, child: Text('Cash on Hand')),
              DropdownMenuItem(value: Accounts.eWallet, child: Text('E-Wallet')),
            ],
            onChanged: (v) => setState(() => _account = v ?? _account),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
              hintText: 'Cheque 004412',
              border: OutlineInputBorder(),
            ),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
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
                  amount: amount,
                  account: _account,
                  reference: _reference.text.trim().isEmpty
                      ? null
                      : _reference.text.trim(),
                )),
          child: const Text('Pay'),
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
    );
  }
}
