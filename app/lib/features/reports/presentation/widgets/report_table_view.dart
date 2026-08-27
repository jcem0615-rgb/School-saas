import 'package:flutter/material.dart';

import '../../domain/entities/report_table.dart';

/// A [ReportTable] on screen: the headline figures, the grid, the note.
///
/// The grid scrolls sideways inside its own box rather than making the
/// page scroll. A report is ten columns wide and a phone is not, and a
/// screen whose whole layout slides left when you drag a table is one
/// where the reader loses the row they were on.
class ReportTableView extends StatelessWidget {
  final ReportTable table;
  const ReportTableView({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(table.title, style: theme.textTheme.titleMedium),
        Text(table.subtitle, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (table.headline.isNotEmpty) ...[
          _Headline(stats: table.headline),
          const SizedBox(height: 16),
        ],
        if (table.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No records fall in this period.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                // Tighter than the Material default, which spaces ten
                // columns wider than a laptop and pushed Rate -- the
                // number the attendance report exists to show -- off the
                // right edge, where the only clue it was there at all
                // was that the table happened to scroll.
                columnSpacing: 18,
                horizontalMargin: 14,
                columns: [
                  for (final column in table.columns)
                    DataColumn(label: Text(column.label), numeric: column.numeric),
                ],
                rows: [
                  for (final row in table.rows)
                    DataRow(
                      color: row.isTotal
                          ? WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest)
                          : null,
                      cells: [
                        for (var i = 0; i < table.columns.length; i++)
                          DataCell(Text(
                            i < row.cells.length ? row.cells[i] : '',
                            style: row.isTotal
                                ? const TextStyle(fontWeight: FontWeight.bold)
                                : null,
                          )),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (table.note != null) ...[
          const SizedBox(height: 12),
          _Note(note: table.note!),
        ],
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  final List<ReportStat> stats;
  const _Headline({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      // Three across on anything wide enough, stacked on a phone. A
      // fixed row would squeeze a peso figure onto two lines, which is
      // the one number on the screen nobody should have to reassemble.
      final columns = constraints.maxWidth > 560 ? stats.length : 1;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final stat in stats)
            SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.label.toUpperCase(),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        stat.value,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (stat.caption != null)
                      Text(
                        stat.caption!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// What the table does not say.
///
/// On the screen and in both exports, never only one of the three. A
/// caveat that lives beside the figures on a monitor and nowhere else is
/// one that gets separated from them the moment anyone prints or mails
/// the report -- which is the whole point of a report.
class _Note extends StatelessWidget {
  final String note;
  const _Note({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = note.startsWith('INCOMPLETE');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? theme.colorScheme.errorContainer : null,
        border: Border.all(
          color: isWarning ? theme.colorScheme.error : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_outlined : Icons.info_outline,
            size: 18,
            color: isWarning ? theme.colorScheme.onErrorContainer : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isWarning ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
