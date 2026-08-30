import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';

final _dayFormat = DateFormat('EEE d MMM');
final _clock = DateFormat('h:mm a');
final _percent = NumberFormat.decimalPercentPattern(decimalDigits: 0);

/// One student's attendance, subject by subject.
///
/// The gate record already said whether they came to school. This says
/// whether they were in the lesson -- which is the question behind a
/// grade that dropped, and the one a parent asks that nobody could
/// answer without walking to the staff room.
///
/// Worst subject first. The reason anybody opens this screen is to find
/// the one that is going wrong, and alphabetical order makes them read
/// all eight to find it.
class SubjectAttendanceScreen extends ConsumerWidget {
  final String studentId;

  /// Named in the title when a parent is looking at one of several
  /// children, so two tabs open side by side are not the same screen.
  final String? studentName;

  const SubjectAttendanceScreen({
    super.key,
    required this.studentId,
    this.studentName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marksAsync = ref.watch(studentSubjectMarksProvider(studentId));
    final summaries = ref.watch(studentSubjectSummaryProvider(studentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(studentName == null
            ? 'Attendance by subject'
            : '$studentName · by subject'),
      ),
      body: marksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('This could not be loaded: $err', textAlign: TextAlign.center),
          ),
        ),
        data: (_) => summaries.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No lessons have been registered yet. Attendance appears '
                    'here once teachers start taking it in class.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final summary in summaries) _SubjectCard(summary: summary),
                ],
              ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectAttendanceSummary summary;
  const _SubjectCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = summary.attendanceRate;
    // Below three quarters is where a school starts asking questions, so
    // that is where the figure stops being a plain number.
    final poor = rate != null && rate < 0.75;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          summary.subject.isEmpty ? 'Unnamed subject' : summary.subject,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${summary.counts.attended} of ${summary.counts.total} lessons'
          '${summary.counts.late == 0 ? '' : ', ${summary.counts.late} late'}'
          '${summary.counts.excused == 0 ? '' : ', ${summary.counts.excused} excused'}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: rate == null
            ? null
            : Text(
                _percent.format(rate),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: poor ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
              ),
        children: [
          for (final mark in summary.marks.take(20)) _MarkRow(mark: mark),
          if (summary.marks.length > 20)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Showing the last 20 of ${summary.marks.length} lessons.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkRow extends StatelessWidget {
  final SubjectAttendanceMark mark;
  const _MarkRow({required this.mark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, colour) = switch (mark.status) {
      AttendanceStatus.present => ('Present', theme.colorScheme.primary),
      AttendanceStatus.late => ('Late', theme.colorScheme.tertiary),
      AttendanceStatus.absent => ('Absent', theme.colorScheme.error),
      AttendanceStatus.excused => ('Excused', theme.colorScheme.outline),
    };

    return ListTile(
      dense: true,
      title: Text(_dateLabel(mark.date), style: theme.textTheme.bodyMedium),
      subtitle: mark.wasThere && mark.timeIn != null
          ? Text(
              mark.timeOut == null
                  ? 'In ${_clock.format(mark.timeIn!)}'
                  : '${_clock.format(mark.timeIn!)} - ${_clock.format(mark.timeOut!)}'
                      '${mark.minutes == null ? '' : ' · ${mark.minutes} min'}',
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: Text(
        label,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: colour, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// The stored key is 'YYYY-MM-DD' in the school's timezone. Parsed
  /// rather than formatted from a DateTime the app made up, so a phone
  /// in another timezone still reads the day the school recorded.
  static String _dateLabel(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    return parsed == null ? dateKey : _dayFormat.format(parsed);
  }
}
