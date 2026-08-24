import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../director_portal/domain/entities/approval_request.dart';
import '../../../director_portal/presentation/controllers/director_controller.dart';
import '../../../director_portal/presentation/widgets/approval_status_badge.dart';

final _dateFormat = DateFormat.yMMMd();
final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// A promissory note (a request to defer a payment) is, structurally, the
/// same "any tenant member files a request, Director/Admin decides it"
/// workflow as Faculty's Material Requests -- reused again here with
/// `type: 'promissory_note'` and the amount/reason carried in [details].
/// No new collection, no new security rule.
class PromissoryNoteScreen extends ConsumerWidget {
  const PromissoryNoteScreen({super.key});

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
      appBar: AppBar(title: const Text('Promissory Note')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRequestDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Request'),
      ),
      body: myRequestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load requests: $err')),
        data: (requests) {
          final notes = requests.where((r) => r.type == 'promissory_note').toList();
          if (notes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No promissory note requests yet. Use this to ask for more time to settle a balance.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = notes[index];
              final amount = (r.details['amount'] as num?)?.toDouble();
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
                      if (amount != null) ...[
                        const SizedBox(height: 4),
                        Text(_currencyFormat.format(amount)),
                      ],
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

  Future<void> _showRequestDialog(BuildContext context, WidgetRef ref) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Promissory Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              final success = await ref.read(directorActionControllerProvider.notifier).createApprovalRequest(
                    type: 'promissory_note',
                    title: 'Payment deferral request',
                    description: reasonController.text,
                    details: {'amount': amount},
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
