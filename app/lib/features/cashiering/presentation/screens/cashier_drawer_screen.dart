import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/cashier_shift.dart';
import '../controllers/cashiering_controller.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateTime = DateFormat('d MMM, h:mm a');
final _time = DateFormat('h:mm a');

/// The cash drawer.
///
/// Opens on whichever state the cashier is in: a drawer running, with
/// what it should hold updating as receipts are written, or no drawer
/// and a button to start one. The history underneath is what makes the
/// control worth having -- a short drawer in March is only interesting
/// next to the eleven that balanced.
class CashierDrawerScreen extends ConsumerWidget {
  const CashierDrawerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shiftsAsync = ref.watch(shiftsProvider);
    final open = ref.watch(myOpenShiftProvider);
    final working = ref.watch(cashieringActionControllerProvider).isLoading;

    ref.listen(cashieringActionControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Drawer')),
      body: shiftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'The drawers could not be read',
          detail: '$e',
        ),
        data: (shifts) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (working) const LinearProgressIndicator(minHeight: 2),
            if (open != null)
              _OpenDrawerCard(shift: open, working: working)
            else
              _NoDrawerCard(working: working),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text('Closed drawers', style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            if (shifts.where((s) => !s.isOpen).isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: _Message(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing counted yet',
                  detail: 'A drawer shows up here once it has been closed.',
                ),
              )
            else
              for (final shift in shifts.where((s) => !s.isOpen))
                _ClosedShiftTile(shift: shift),
          ],
        ),
      ),
    );
  }
}

class _NoDrawerCard extends ConsumerWidget {
  final bool working;
  const _NoDrawerCard({required this.working});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No drawer open', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Count the float and open one. Everything you take in cash '
              'from that moment is in the reckoning — nothing has to be '
              'tagged, so nothing can be missed.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: working ? null : () => _open(context, ref),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Open a drawer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: '0.00');
    final notes = TextEditingController();
    final float = await showDialog<({double amount, String? notes})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open a drawer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Count what is in the drawer before you start. A float taken '
              'on trust is a difference that was always there and nobody '
              'can date.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening float',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
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
            onPressed: () => Navigator.of(dialogContext).pop((
              amount: double.tryParse(controller.text.trim()) ?? 0,
              notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
            )),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (float == null || !context.mounted) return;

    final ok = await ref.read(cashieringActionControllerProvider.notifier).openShift(
          openShift: ref.read(myOpenShiftProvider),
          openingFloat: float.amount,
          notes: float.notes,
        );
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Drawer open.')));
    }
  }
}

class _OpenDrawerCard extends ConsumerWidget {
  final CashierShift shift;
  final bool working;
  const _OpenDrawerCard({required this.shift, required this.working});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reckoning = ref.watch(reckoningProvider(shift)).valueOrNull;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.point_of_sale_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Drawer open since ${_time.format(shift.openedAt)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (reckoning == null)
              const LinearProgressIndicator(minHeight: 2)
            else ...[
              // Shown while the drawer is running, not only at close: a
              // figure that appears afterwards is one a cashier cannot
              // check themselves against.
              _Figure(label: 'Opening float', amount: reckoning.openingFloat),
              _Figure(
                label: 'Collected (${reckoning.receiptCount} receipts)',
                amount: reckoning.cashCollected,
              ),
              if (reckoning.cashRefunded > 0)
                _Figure(label: 'Refunded', amount: -reckoning.cashRefunded),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('Should be in the drawer',
                        style: theme.textTheme.titleSmall),
                  ),
                  Text(_money.format(reckoning.expected),
                      style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_money.format(reckoning.toDeposit)} to bank — the float '
                'stays for tomorrow.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: working
                    ? null
                    : () => _close(context, ref, reckoning.expected),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Count and close'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    double expected,
  ) async {
    final result = await showDialog<({double counted, String note})>(
      context: context,
      builder: (_) => _CloseDrawerDialog(expected: expected),
    );
    if (result == null || !context.mounted) return;

    final closing =
        await ref.read(cashieringActionControllerProvider.notifier).closeShift(
              shift: shift,
              countedAmount: result.counted,
              expectedAmount: expected,
              varianceNote: result.note,
            );
    if (closing == null || !context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          closing.variance.abs() < 0.005
              ? 'Drawer closed and balanced.'
              : 'Drawer closed. '
                  '${closing.variance < 0 ? 'Short' : 'Over'} '
                  '${_money.format(closing.variance.abs())}.',
        ),
      ));
  }
}

class _CloseDrawerDialog extends StatefulWidget {
  final double expected;
  const _CloseDrawerDialog({required this.expected});

  @override
  State<_CloseDrawerDialog> createState() => _CloseDrawerDialogState();
}

class _CloseDrawerDialogState extends State<_CloseDrawerDialog> {
  final _counted = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _counted.text.trim();
    final counted = double.tryParse(typed);
    final variance = counted == null ? null : counted - widget.expected;
    final differs = variance != null && variance.abs() >= 0.005;
    final needsNote = differs && _note.text.trim().length < 4;

    return AlertDialog(
      title: const Text('Count the drawer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The expected figure is on screen, but the count goes in
          // first and the difference only appears afterwards. A box
          // pre-filled with what it should be is a box that gets
          // accepted without counting.
          TextField(
            controller: _counted,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Counted',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Expected ${_money.format(widget.expected)}',
              style: theme.textTheme.bodyMedium),
          if (variance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                differs
                    ? '${variance < 0 ? 'Short' : 'Over'} '
                        '${_money.format(variance.abs())}'
                    : 'Balanced',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: differs
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          if (differs) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'What happened',
                hintText: 'Gave the wrong change this morning',
                border: const OutlineInputBorder(),
                errorText: needsNote ? 'A difference needs an explanation.' : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'It does not have to be a good reason. "No idea" on the '
              'record beats nothing on the record.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: counted == null || counted < 0 || needsNote
              ? null
              : () => Navigator.of(context)
                  .pop((counted: counted, note: _note.text.trim())),
          child: const Text('Close drawer'),
        ),
      ],
    );
  }
}

class _ClosedShiftTile extends StatelessWidget {
  final CashierShift shift;
  const _ClosedShiftTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = shift.isBalanced
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.error;

    return ListTile(
      leading: Icon(
        shift.isBalanced ? Icons.check_circle_outline : Icons.error_outline,
        color: colour,
      ),
      title: Text('${shift.cashierName} · ${_dateTime.format(shift.openedAt)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Counted ${_money.format(shift.countedAmount ?? 0)} against '
            '${_money.format(shift.expectedAmount ?? 0)}',
            style: theme.textTheme.bodySmall,
          ),
          if (shift.varianceNote != null)
            Text(shift.varianceNote!, style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: shift.varianceNote != null,
      trailing: Text(
        shift.varianceLabel(),
        style: theme.textTheme.titleSmall?.copyWith(color: colour),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final double amount;
  const _Figure({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(_money.format(amount), style: theme.textTheme.bodyMedium),
        ],
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
