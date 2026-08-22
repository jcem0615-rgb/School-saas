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
            Text('${request.requestedByName} (${request.requestedByRole}) · ${_dateFormat.format(request.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (request.description != null) ...[
              const SizedBox(height: 8),
              Text(request.description!),
            ],
            if (request.status != ApprovalStatus.pending && request.decisionRemarks != null) ...[
              const SizedBox(height: 8),
              Text('Remarks: ${request.decisionRemarks}', style: Theme.of(context).textTheme.bodySmall),
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
