import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/leave_request.dart';
import '../controllers/timekeeping_controller.dart';
import '../widgets/leave_tile.dart';

/// The office's queue: what is waiting to be decided, and what was.
///
/// Both halves on one screen, deliberately. A queue that empties into
/// nowhere is a queue nobody can check afterwards -- "did anyone ever
/// answer my leave form" is the question this screen exists to make
/// answerable, and it is asked far more often than the queue is worked.
class LeaveRequestsScreen extends ConsumerWidget {
  const LeaveRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allLeaveProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave requests')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('This could not be loaded: $err', textAlign: TextAlign.center),
          ),
        ),
        data: (all) {
          final pending = all.where((r) => r.isPending).toList();
          final decided = all.where((r) => !r.isPending).toList();

          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nobody has filed leave yet. Requests appear here as staff '
                  'file them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            children: [
              _SectionHeader(
                label: pending.isEmpty
                    ? 'Nothing waiting'
                    : pending.length == 1
                        ? '1 waiting on you'
                        : '${pending.length} waiting on you',
                emphasis: pending.isNotEmpty,
              ),
              for (final request in pending)
                LeaveTile(
                  request: request,
                  showEmployee: true,
                  onApprove: () => _decide(context, ref, request, true),
                  onDecline: () => _decide(context, ref, request, false),
                ),
              if (decided.isNotEmpty) ...[
                const _SectionHeader(label: 'Already decided'),
                for (final request in decided)
                  LeaveTile(request: request, showEmployee: true),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  // Said plainly, because the connection is not obvious
                  // and getting it wrong costs somebody a day's pay.
                  'Approved leave shows on that employee\'s timesheet as leave '
                  'rather than absence. A request left pending does not.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    LeaveRequest request,
    bool approved,
  ) async {
    final remarks = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approved ? 'Approve this leave?' : 'Decline this leave?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.employeeName} · ${request.type.displayLabel} · '
              '${request.days} working day${request.days == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarks,
              decoration: InputDecoration(
                labelText: 'Remarks (optional)',
                hintText: approved
                    ? 'Anything the employee should know'
                    : 'Why, so they are not left guessing',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approved ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );

    final text = remarks.text;
    remarks.dispose();
    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(timekeepingActionControllerProvider.notifier)
        .decideLeave(
          requestId: request.id,
          approved: approved,
          remarks: text,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (approved ? 'Approved.' : 'Declined.')
          : 'That decision could not be saved.'),
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool emphasis;
  const _SectionHeader({required this.label, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: emphasis ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
