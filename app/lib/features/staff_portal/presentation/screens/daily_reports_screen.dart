import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controllers/staff_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class DailyReportsScreen extends ConsumerStatefulWidget {
  const DailyReportsScreen({super.key});

  @override
  ConsumerState<DailyReportsScreen> createState() => _DailyReportsScreenState();
}

class _DailyReportsScreenState extends ConsumerState<DailyReportsScreen> {
  /// Null means "show every report". Picking a date filters to that day.
  DateTime? _filterDate;

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _filterDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(myDailyReportsProvider);

    ref.listen(staffActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Filter by date',
            onPressed: _pickDate,
          ),
          if (_filterDate != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Show all dates',
              onPressed: () => setState(() => _filterDate = null),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSubmitDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Submit Report'),
      ),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load reports: $err')),
        data: (allReports) {
          // Reports are keyed by a 'YYYY-MM-DD' string, so the filter
          // compares on that rather than on a DateTime, which would drag
          // timezone handling into a field that has no time component.
          final reports = _filterDate == null
              ? allReports
              : allReports.where((r) => r.date == _dateKey(_filterDate!)).toList();

          if (reports.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _filterDate == null
                      ? 'No reports submitted yet.'
                      : 'No report for ${_dateFormat.format(_filterDate!)}.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
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
