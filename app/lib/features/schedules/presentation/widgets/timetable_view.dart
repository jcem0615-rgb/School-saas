import 'package:flutter/material.dart';

import '../../domain/entities/schedule_block.dart';

/// A week of classes, grouped by day.
///
/// A list rather than the grid a timetable is usually drawn as, and that
/// is a phone decision. A five-by-ten grid on a 390pt screen is either
/// unreadable or scrolls in two directions at once; a day at a time with
/// the time down the left reads on any width. The grid is where it
/// belongs -- on the printed sheet that goes on the wall.
///
/// Empty days are dropped rather than shown blank. A school with no
/// Saturday classes should not scroll past an empty Saturday every time
/// it checks Friday.
class TimetableView extends StatelessWidget {
  final List<ScheduleBlock> blocks;

  /// What to say when there is nothing at all.
  final String emptyMessage;

  /// Shown under each class instead of the section -- used on a
  /// section's own timetable, where repeating the section on every row
  /// says nothing.
  final bool showSection;
  final bool showTeacher;
  final void Function(ScheduleBlock block)? onTap;

  /// The day to lead with, so "today" is the first thing on screen
  /// rather than Monday on a Thursday afternoon.
  final int? highlightDay;

  const TimetableView({
    super.key,
    required this.blocks,
    this.emptyMessage = 'Nothing is timetabled yet.',
    this.showSection = true,
    this.showTeacher = true,
    this.onTap,
    this.highlightDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(emptyMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final byDay = <int, List<ScheduleBlock>>{};
    for (final block in blocks) {
      (byDay[block.dayOfWeek] ??= []).add(block);
    }
    for (final day in byDay.values) {
      day.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    }
    final days = byDay.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Text(
                  weekdayLabel(day),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: day == highlightDay ? theme.colorScheme.primary : null,
                    fontWeight: day == highlightDay ? FontWeight.w700 : null,
                  ),
                ),
                if (day == highlightDay) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Today',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final block in byDay[day]!)
            _BlockTile(
              block: block,
              showSection: showSection,
              showTeacher: showTeacher,
              onTap: onTap == null ? null : () => onTap!(block),
            ),
        ],
      ],
    );
  }
}

class _BlockTile extends StatelessWidget {
  final ScheduleBlock block;
  final bool showSection;
  final bool showTeacher;
  final VoidCallback? onTap;

  const _BlockTile({
    required this.block,
    required this.showSection,
    required this.showTeacher,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (showSection) block.section,
      if (showTeacher) block.teacherName,
      if (block.room != null) block.room!,
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The time reads down the left edge like a printed
              // timetable, so a column of start times can be scanned
              // without reading any of the subjects.
              SizedBox(
                width: 76,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.startLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      block.endLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(block.subject, style: theme.textTheme.titleSmall),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
