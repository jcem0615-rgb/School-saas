import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/approval_request.dart';
import '../controllers/director_controller.dart';
import '../widgets/approval_status_badge.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  ApprovalStatus? _filter = ApprovalStatus.pending;

  @override
  Widget build(BuildContext context) {
    final approvalsAsync = ref.watch(approvalsStreamProvider(_filter));

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Pending'),
                    selected: _filter == ApprovalStatus.pending,
                    onSelected: (_) => setState(() => _filter = ApprovalStatus.pending),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Approved'),
                    selected: _filter == ApprovalStatus.approved,
                    onSelected: (_) => setState(() => _filter = ApprovalStatus.approved),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Rejected'),
                    selected: _filter == ApprovalStatus.rejected,
                    onSelected: (_) => setState(() => _filter = ApprovalStatus.rejected),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: approvalsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load approvals: $err')),
              data: (approvals) {
                if (approvals.isEmpty) {
                  return const Center(child: Text('Nothing here.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: approvals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ApprovalTile(request: approvals[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalTile extends ConsumerWidget {
  final ApprovalRequest request;
  const _ApprovalTile({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(request.title, style: Theme.of(context).textTheme.titleMedium)),
                ApprovalStatusBadge(status: request.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Filed by ${request.requestedByName} (${_roleLabel(request.requestedByRole)}) '
              '· ${_dateFormat.format(request.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (request.description != null) ...[
              const SizedBox(height: 8),
              Text(request.description!),
            ],
            // What is actually being decided. A request whose details are
            // hidden is one that gets approved on its title, and a
            // decision recorded against a title nobody can reconstruct is
            // not much of a record afterwards.
            if (request.details.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailTable(details: request.details),
            ],
            if (request.isDecided) ...[
              const SizedBox(height: 12),
              _DecisionBlock(request: request),
            ],
            if (request.status == ApprovalStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _showRejectDialog(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => ref
                        .read(directorActionControllerProvider.notifier)
                        .decideApproval(approvalId: request.id, approve: true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRejectDialog(BuildContext context, WidgetRef ref) async {
    final remarksController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this request?'),
        content: TextField(
          controller: remarksController,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(directorActionControllerProvider.notifier).decideApproval(
            approvalId: request.id,
            approve: false,
            remarks: remarksController.text,
          );
    }
  }
}

/// Roles are stored as the snake_case value the rules check against.
String _roleLabel(String role) => role
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Turns a stored key into something a person reads: `requestedAmount`
/// and `needed_by` both become "Needed by"-shaped labels rather than
/// being printed as the field names they are in the database.
String _detailLabel(String key) {
  final spaced = key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();
  if (spaced.isEmpty) return key;
  return '${spaced[0].toUpperCase()}${spaced.substring(1).toLowerCase()}';
}

String _detailValue(Object? value) {
  if (value == null) return '-';
  if (value is num) {
    // Amounts are the common case here (a promissory note, a material
    // request's cost), and a bare 5000 in a money column reads wrong.
    return value == value.roundToDouble() && value.abs() < 1000000000
        ? NumberFormat('#,##0.##').format(value)
        : value.toString();
  }
  if (value is DateTime) return _dateFormat.format(value);
  if (value is List) return value.join(', ');
  return value.toString();
}

/// The request's own fields, whatever they are.
///
/// `details` is deliberately free-form -- a material request and a
/// promissory note file into the same collection -- so this renders
/// whatever it finds rather than knowing about either.
class _DetailTable extends StatelessWidget {
  final Map<String, dynamic> details;
  const _DetailTable({required this.details});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in details.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      _detailLabel(entry.key),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _detailValue(entry.value),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Who decided, in what role, when, and why.
///
/// The card used to show the remarks alone, so a decided request could
/// not say who had decided it -- which is the first question asked about
/// one weeks later.
class _DecisionBlock extends StatelessWidget {
  final ApprovalRequest request;
  const _DecisionBlock({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approved = request.status == ApprovalStatus.approved;
    final tone = approved
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.errorContainer;
    final onTone = approved
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onErrorContainer;

    final who = request.decidedByName;
    final role = request.decidedByRole;
    final when = request.decidedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 18,
                color: onTone,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // Named even when the record predates this being
                  // stored, rather than silently printing nothing: an
                  // unattributed decision should look unattributed.
                  who == null
                      ? '${approved ? 'Approved' : 'Declined'} - decided by is not on record'
                      : '${approved ? 'Approved' : 'Declined'} by $who'
                          '${role == null ? '' : ' (${_roleLabel(role)})'}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: onTone),
                ),
              ),
            ],
          ),
          if (when != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(
                _dateFormat.format(when),
                style: theme.textTheme.bodySmall?.copyWith(color: onTone),
              ),
            ),
          if (request.decisionRemarks != null &&
              request.decisionRemarks!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 24),
              child: Text(
                'Reason: ${request.decisionRemarks}',
                style: theme.textTheme.bodySmall?.copyWith(color: onTone),
              ),
            ),
        ],
      ),
    );
  }
}
