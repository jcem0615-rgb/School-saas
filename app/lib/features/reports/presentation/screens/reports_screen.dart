import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data_transfer/workbook.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../domain/entities/report_kind.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_table.dart';
import '../controllers/reports_controller.dart';
import '../documents/report_pdf.dart';
import '../widgets/report_table_view.dart';

/// The school's reports, in one place.
///
/// Director and Admin only, and that is a rules constraint rather than a
/// product decision: they are the two roles with an unconditional read
/// on students, payments, grades and attendance. A principal's reads are
/// scoped per document, so a school-wide list query from that account is
/// refused outright -- a division-scoped report is real work, not a
/// filter on this one, and it is not pretended at here.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(reportRequestProvider);
    final tableAsync = ref.watch(reportTableProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(reportTableProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _KindPicker(selected: request.kind),
          const SizedBox(height: 12),
          if (request.kind.usesPeriod) _PeriodPicker(period: request.period),
          const SizedBox(height: 16),
          tableAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => _Failure(message: err.toString()),
            data: (table) => _Report(table: table),
          ),
        ],
      ),
    );
  }
}

class _KindPicker extends ConsumerWidget {
  final ReportKind selected;
  const _KindPicker({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in ReportKind.values)
              ChoiceChip(
                label: Text(kind.title),
                selected: kind == selected,
                onSelected: (_) => ref.read(reportRequestProvider.notifier).update(
                      // The term filter belongs to whichever report was
                      // showing; carrying it onto the next one would
                      // silently narrow a report that never asked for it.
                      (state) => state.copyWith(kind: kind, term: null),
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(selected.blurb, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PeriodPicker extends ConsumerWidget {
  final ReportPeriod period;
  const _PeriodPicker({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void setPeriod(ReportPeriod next) =>
        ref.read(reportRequestProvider.notifier).update((s) => s.copyWith(period: next));

    Future<void> pickCustom() async {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: period.start, end: period.end),
      );
      if (picked != null) setPeriod(ReportPeriod(picked.start, picked.end));
    }

    final now = DateTime.now();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.date_range_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(period.label, style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(onPressed: pickCustom, child: const Text('Change')),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('This school year'),
                  onPressed: () => setPeriod(ReportPeriod.schoolYearOf(now)),
                ),
                ActionChip(
                  label: const Text('This month'),
                  onPressed: () => setPeriod(ReportPeriod.monthOf(now)),
                ),
                ActionChip(
                  label: const Text('Last 30 days'),
                  onPressed: () => setPeriod(ReportPeriod.lastDays(30, endingOn: now)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Report extends ConsumerStatefulWidget {
  final ReportTable table;
  const _Report({required this.table});

  @override
  ConsumerState<_Report> createState() => _ReportState();
}

class _ReportState extends ConsumerState<_Report> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      // Headline figures ride along above the table rather than being
      // dropped. Somebody mailing this file is mailing the report, not a
      // grid of numbers, and the two or three figures they quoted in the
      // covering email have to be in it.
      final rows = <List<String>>[
        for (final stat in widget.table.headline)
          [stat.label, stat.value, if (stat.caption != null) stat.caption!],
        if (widget.table.headline.isNotEmpty) const [],
        widget.table.headers,
        ...widget.table.cellRows,
        if (widget.table.note != null) ...[const [], ['About these figures', widget.table.note!]],
      ];
      final bytes = Workbook.encode(
        [widget.table.title, widget.table.subtitle],
        rows,
        sheetName: 'Report',
      );
      final slug = widget.table.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await FilePicker.saveFile(
        fileName: '$slug-${DateTime.now().toIso8601String().substring(0, 10)}.xlsx',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      await ReportPdf.print(
        table: widget.table,
        branding: ref.read(brandingProvider).valueOrNull ?? SchoolBranding.empty,
        preparedByName: ref.read(authStateProvider).valueOrNull?.fullName ?? 'the office',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final term = ref.watch(reportRequestProvider).term;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (table.filterOptions.isNotEmpty) ...[
          Text(table.filterLabel ?? 'Filter', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: term == null,
                onSelected: (_) =>
                    ref.read(reportRequestProvider.notifier).update((s) => s.copyWith(term: null)),
              ),
              for (final option in table.filterOptions)
                ChoiceChip(
                  label: Text(option),
                  selected: term == option,
                  onSelected: (_) => ref
                      .read(reportRequestProvider.notifier)
                      .update((s) => s.copyWith(term: option)),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        ReportTableView(table: table),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || table.isEmpty ? null : _export,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export to Excel'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || table.isEmpty ? null : _print,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
            ),
          ],
        ),
        if (table.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'There is nothing to export or print until the report has rows.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  final String message;
  const _Failure({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
