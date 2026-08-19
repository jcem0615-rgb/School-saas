import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../director_portal/domain/entities/approval_request.dart';
import '../../../director_portal/presentation/controllers/director_controller.dart';
import '../../../director_portal/presentation/widgets/approval_status_badge.dart';

final _dateFormat = DateFormat.yMMMd();

/// Faculty's "Material Requests" is the exact same generic approvals
/// mechanism Director Portal built for deciding requests -- this screen
/// only adds the filing side (`type: 'material_request'`) and a view
/// scoped to the current user's own requests. No new collection, no new
/// security rule beyond what Director Portal's approvals block already
/// defines (any active tenant member may file; only Director/Admin decide).
class MaterialRequestsScreen extends ConsumerWidget {
  const MaterialRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRequestsAsync = ref.watch(myApprovalsStreamProvider);

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Material Requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
      body: myRequestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load requests: $err')),
        data: (requests) {
          final materialRequests = requests.where((r) => r.type == 'material_request').toList();
          if (materialRequests.isEmpty) {
            return const Center(child: Text('No material requests filed yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: materialRequests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = materialRequests[index];
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
                          Expanded(child: Text(r.title, style: Theme.of(context).textTheme.titleMedium)),
                          ApprovalStatusBadge(status: r.status),
                        ],
                      ),
                      if (r.description != null) ...[
                        const SizedBox(height: 6),
                        Text(r.description!),
                      ],
                      const SizedBox(height: 6),
                      Text('Filed ${_dateFormat.format(r.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                      if (r.status != ApprovalStatus.pending && r.decisionRemarks != null) ...[
                        const SizedBox(height: 6),
                        Text('Response: ${r.decisionRemarks}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Material Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'What do you need?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final success = await ref.read(directorActionControllerProvider.notifier).createApprovalRequest(
                    type: 'material_request',
                    title: titleController.text,
                    description: descriptionController.text,
                  );
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
