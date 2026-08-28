import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../../../core/constants/user_roles.dart';
import '../../domain/entities/data_request.dart';
import '../controllers/data_protection_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// Where a person exercises the rights the notice describes.
///
/// In the app rather than only in the office, because a right you have
/// to find the right window and the right hour to exercise is one most
/// people never exercise. The office still answers it -- this is the
/// front door, not the decision.
class MyDataScreen extends ConsumerWidget {
  const MyDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(myDataRequestsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('My information')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ask the school for a copy of what it holds about you, to have '
            'something corrected, or to object to how it is used. The school '
            'office answers these.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (user?.role == UserRole.parent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You can ask about your own information and about a child '
                'linked to your account. Say which child in the request.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          for (final kind in DataRequestKind.values)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: ListTile(
                title: Text(kind.displayLabel),
                subtitle: Text(kind.blurb),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _raise(context, ref, kind),
              ),
            ),
          const Divider(height: 32),
          Text('What you have asked for', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          requestsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text('These could not be loaded: $err'),
            data: (requests) => requests.isEmpty
                ? Text(
                    'Nothing yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: [for (final request in requests) _RequestTile(request: request)],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _raise(BuildContext context, WidgetRef ref, DataRequestKind kind) async {
    final controller = TextEditingController();
    final details = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(kind.displayLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kind.blurb, style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'What are you asking for?',
                hintText: switch (kind) {
                  DataRequestKind.access => 'e.g. everything on file for my son Miguel',
                  DataRequestKind.correction => 'e.g. my birth date is wrong on my ID',
                  DataRequestKind.erasure => 'e.g. please remove my old phone number',
                  DataRequestKind.objection => 'e.g. I do not want my photo on the roster',
                },
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
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (details == null || !context.mounted) return;

    final ok = await ref.read(dataProtectionActionControllerProvider.notifier).raise(
          kind: kind,
          details: details,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? 'Sent. The school office will answer this.'
            : 'That could not be sent. Say what you are asking for and try again.'),
      ));
  }
}

class _RequestTile extends StatelessWidget {
  final DataRequest request;
  const _RequestTile({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(request.kind.displayLabel, style: theme.textTheme.titleSmall),
                ),
                Chip(
                  label: Text(request.status.displayLabel),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              _dateFormat.format(request.requestedAt),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(request.details, style: theme.textTheme.bodyMedium),
            if (request.outcome != null) ...[
              const SizedBox(height: 8),
              // The school's answer, shown to the person who asked --
              // including a refusal. A refusal they are never told about
              // is the same as no answer.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The school said',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(request.outcome!, style: theme.textTheme.bodySmall),
                    if (request.handledByName != null)
                      Text(
                        '${request.handledByName}'
                        '${request.handledAt == null ? '' : ' · ${_dateFormat.format(request.handledAt!)}'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
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
