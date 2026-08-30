import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/leave_request.dart';
import '../../domain/entities/timesheet.dart';
import '../controllers/timekeeping_controller.dart';
import '../widgets/leave_tile.dart';

final _dayFormat = DateFormat('d MMM y');

/// An employee's own leave: what they have filed, and what became of it.
class MyLeaveScreen extends ConsumerWidget {
  const MyLeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLeaveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My leave')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFileLeaveSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('File leave'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('This could not be loaded: $err', textAlign: TextAlign.center),
          ),
        ),
        data: (requests) => requests.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'You have not filed any leave. Anything you file appears '
                    'here with the office\'s decision on it.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => LeaveTile(
                  request: requests[i],
                  // The employee's own view: they may withdraw what has
                  // not been decided, and nothing else.
                  onCancel: requests[i].isPending
                      ? () => _cancel(context, ref, requests[i])
                      : null,
                ),
              ),
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    LeaveRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text(
          '${request.type.displayLabel}, ${_dayFormat.format(DateTime.parse(request.fromDate))} '
          'to ${_dayFormat.format(DateTime.parse(request.toDate))}. '
          'It stays on your record as withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(timekeepingActionControllerProvider.notifier)
        .cancelLeave(request.id);
  }
}

/// The filing form.
///
/// A sheet rather than a screen, matching every other create form in
/// this app, and shared between the employee's own list and anywhere
/// else that grows a way in.
Future<void> showFileLeaveSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FileLeaveSheet(),
  );
}

class _FileLeaveSheet extends ConsumerStatefulWidget {
  const _FileLeaveSheet();

  @override
  ConsumerState<_FileLeaveSheet> createState() => _FileLeaveSheetState();
}

class _FileLeaveSheetState extends ConsumerState<_FileLeaveSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  LeaveType _type = LeaveType.sick;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      // A year back, because leave is sometimes filed after the fact --
      // nobody fills in a form from a hospital bed -- and a year ahead,
      // which covers the longest leave a school year contains.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // Dragging the start past the end is a mistake, not an
        // instruction. Move the end rather than refuse the pick.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(timekeepingActionControllerProvider.notifier).fileLeave(
          type: _type,
          from: _from,
          to: _to,
          reason: _reason.text,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Filed. The office will see it in their queue.'
          : 'That could not be filed. Try again.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = ref.watch(timekeepingActionControllerProvider).isLoading;
    final days = workingDaysBetween(_from, _to);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('File leave', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<LeaveType>(
              initialValue: _type,
              // Without isExpanded the button takes the width of its
              // widest item, and "Maternity or paternity leave" pushes
              // it 192 pixels off the right of a phone.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kind of leave'),
              items: [
                for (final type in LeaveType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type.displayLabel, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _from,
                    onTap: () => _pick(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _to,
                    onTap: () => _pick(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              days == 0
                  // Weekends only. Worth saying out loud rather than
                  // filing a request the timesheet will never use.
                  ? 'No working days in that range.'
                  : days == 1
                      ? '1 working day.'
                      : '$days working days.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: days == 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'What the office needs to know',
              ),
              maxLines: 3,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Say why, so the office can decide.'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (busy || days == 0) ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('File it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(_dayFormat.format(value)),
      ),
    );
  }
}
