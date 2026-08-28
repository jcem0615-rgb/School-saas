import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/data_request.dart';
import '../controllers/data_protection_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// The office's queue of requests about personal information.
///
/// Open ones first, oldest at the top, with the days they have been
/// waiting on the face of each. A queue sorted newest-first is a queue
/// where the request somebody has been waiting a month for sinks out of
/// sight, which is the only failure mode this screen exists to prevent.
class DataRequestsScreen extends ConsumerWidget {
  const DataRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(dataRequestsProvider);

    ref.listen(dataProtectionActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Data Requests')),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('These could not be loaded: $err'),
          ),
        ),
        data: (all) {
          final open = all.where((r) => r.isOpen).toList()
            ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
          final closed = all.where((r) => !r.isOpen).toList();
          final overdue = open.where((r) => r.isOverdue()).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: overdue > 0
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        open.isEmpty
                            ? 'Nothing waiting'
                            : '${open.length} waiting'
                                '${overdue > 0 ? ', $overdue past ${DataRequest.targetDays} days' : ''}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A person who asks about their own information is '
                        'entitled to an answer, including when the answer is '
                        'no. Closing a request needs a reason either way.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (open.isNotEmpty) ...[
                Text('Waiting', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final request in open)
                  _RequestCard(
                    request: request,
                    onClose: () => _close(context, ref, request),
                  ),
                const SizedBox(height: 16),
              ],
              if (closed.isNotEmpty) ...[
                Text('Answered', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final request in closed) _RequestCard(request: request),
              ],
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No one has asked yet.\n\n'
                    'Families can raise a request from Privacy in their own '
                    'profile. They arrive here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref, DataRequest request) async {
    final outcomeController = TextEditingController();
    var status = DataRequestStatus.actioned;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Answer this request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.details, style: Theme.of(dialogContext).textTheme.bodyMedium),
                const SizedBox(height: 12),
                SegmentedButton<DataRequestStatus>(
                  segments: const [
                    ButtonSegment(value: DataRequestStatus.actioned, label: Text('Done')),
                    ButtonSegment(value: DataRequestStatus.refused, label: Text('Refused')),
                  ],
                  selected: {status},
                  onSelectionChanged: (s) => setState(() => status = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outcomeController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: status == DataRequestStatus.refused
                        ? 'Why it is being refused'
                        : 'What was done',
                    // A refusal has to stand on its own to the person
                    // reading it, who will not be looking at this queue.
                    hintText: status == DataRequestStatus.refused
                        ? 'e.g. the transcript is a record the school is required to keep'
                        : 'e.g. printed and handed over at the registrar on 3 September',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final outcome = outcomeController.text;
    outcomeController.dispose();
    if (confirmed != true || !context.mounted) return;

    await ref.read(dataProtectionActionControllerProvider.notifier).close(
          requestId: request.id,
          status: status,
          outcome: outcome,
        );
  }
}

class _RequestCard extends StatelessWidget {
  final DataRequest request;
  final VoidCallback? onClose;

  const _RequestCard({required this.request, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = request.isOverdue();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: overdue ? theme.colorScheme.error : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request.kind.displayLabel} - ${request.subjectLabel}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (request.isOpen)
                  Text(
                    '${request.daysOpen()}d',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: overdue ? theme.colorScheme.error : theme.colorScheme.outline,
                      fontWeight: overdue ? FontWeight.w700 : null,
                    ),
                  )
                else
                  Chip(
                    label: Text(request.status.displayLabel),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Text(
              'Asked by ${request.requestedByName} on '
              '${_dateFormat.format(request.requestedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(request.details, style: theme.textTheme.bodyMedium),
            if (request.outcome != null) ...[
              const SizedBox(height: 8),
              Text(
                request.outcome!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (request.handledByName != null)
                Text(
                  '${request.handledByName}'
                  '${request.handledAt == null ? '' : ' · ${_dateFormat.format(request.handledAt!)}'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
            if (onClose != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onClose, child: const Text('Answer')),
              ),
          ],
        ),
      ),
    );
  }
}
