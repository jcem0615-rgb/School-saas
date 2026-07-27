import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controllers/staff_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class DailyReportsScreen extends ConsumerWidget {
  const DailyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(myDailyReportsProvider);

    ref.listen(staffActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Reports')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSubmitDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Submit Report'),
      ),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load reports: $err')),
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(child: Text('No reports submitted yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = reports[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text(_dateFormat.format(DateTime.parse(r.date))),
                  subtitle: Text(r.content),
                  isThreeLine: r.content.length > 60,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showSubmitDialog(BuildContext context, WidgetRef ref) async {
    final contentController = TextEditingController();
    final date = DateTime.now().toIso8601String().substring(0, 10);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit Daily Report'),
        content: TextField(
          controller: contentController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'What did you work on today?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final success = await ref
                  .read(staffActionControllerProvider.notifier)
                  .submitDailyReport(date: date, content: contentController.text);
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
