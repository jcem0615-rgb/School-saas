import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/leave_request.dart';

final _dayFormat = DateFormat('d MMM');
final _decidedFormat = DateFormat('d MMM y, h:mm a');

/// One request, in whichever list it appears in.
///
/// The same widget for the employee's own list and the office's queue,
/// because the row says the same things in both -- who, what kind, which
/// days, and what was decided. What differs is which buttons it carries,
/// and those are passed in.
class LeaveTile extends StatelessWidget {
  final LeaveRequest request;

  /// Shows the employee's name. Off in their own list, where it would be
  /// their own name on every row.
  final bool showEmployee;

  final VoidCallback? onCancel;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  const LeaveTile({
    super.key,
    required this.request,
    this.showEmployee = false,
    this.onCancel,
    this.onApprove,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = DateTime.tryParse(request.fromDate);
    final to = DateTime.tryParse(request.toDate);
    final range = (from == null || to == null)
        ? '${request.fromDate} to ${request.toDate}'
        : request.fromDate == request.toDate
            ? _dayFormat.format(from)
            : '${_dayFormat.format(from)} - ${_dayFormat.format(to)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showEmployee)
                      Text(
                        request.employeeName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    Text(
                      '${request.type.displayLabel} · $range',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      request.days == 1 ? '1 working day' : '${request.days} working days',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          if (request.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(request.reason, style: theme.textTheme.bodySmall),
          ],
          if (request.status.isDecided) ...[
            const SizedBox(height: 6),
            Text(
              // Who decided, in what role, and when -- the same three
              // things the approval history records, and for the same
              // reason: a decision nobody can attribute is a decision
              // nobody can question.
              '${request.status.displayLabel} by ${request.decidedByName ?? 'the office'}'
              '${request.decidedByRole == null ? '' : ' (${request.decidedByRole})'}'
              '${request.decidedAt == null ? '' : ' on ${_decidedFormat.format(request.decidedAt!)}'}'
              '${request.decisionRemarks == null ? '' : ' - ${request.decisionRemarks}'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (onCancel != null || onApprove != null || onDecline != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onCancel != null)
                  TextButton(onPressed: onCancel, child: const Text('Withdraw')),
                if (onDecline != null)
                  TextButton(onPressed: onDecline, child: const Text('Decline')),
                if (onApprove != null)
                  FilledButton(onPressed: onApprove, child: const Text('Approve')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final LeaveStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = switch (status) {
      LeaveStatus.approved => theme.colorScheme.primary,
      LeaveStatus.declined => theme.colorScheme.error,
      LeaveStatus.cancelled => theme.colorScheme.outline,
      LeaveStatus.pending => theme.colorScheme.tertiary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.displayLabel,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: colour, fontWeight: FontWeight.w700),
      ),
    );
  }
}
