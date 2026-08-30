import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';

final _clock = DateFormat('h:mm a');

/// The register for one class.
///
/// Everybody is present when it opens, and the teacher taps the
/// exceptions. Three taps for three absences rather than forty taps for
/// a full class -- and, more to the point, a class that ran to the bell
/// and was never fully marked still recorded the truth about the
/// thirty-seven children who were there.
class ClassRollScreen extends ConsumerWidget {
  final String sessionId;
  const ClassRollScreen({super.key, required this.sessionId});

  Future<void> _timeOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End this class?'),
        content: const Text(
          'The finish time is recorded against everyone who was here. You '
          'can still correct the register today.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Time out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final controller = ref.read(classSessionActionControllerProvider.notifier);
    final ok = await controller.closeSession(sessionId);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(controller.errorMessage ?? 'The class could not be ended.'),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(classSessionProvider(sessionId));
    final rollAsync = ref.watch(classRollProvider(sessionId));
    final busy = ref.watch(classSessionActionControllerProvider).isLoading;
    final theme = Theme.of(context);

    final session = sessionAsync.valueOrNull;
    final roll = rollAsync.valueOrNull ?? const <SubjectAttendanceMark>[];
    // Counted from the marks rather than read off the session, because
    // the session's own counts are written at Time Out and this has to
    // be right while the teacher is still marking.
    final counts = RollCounts.of(roll);

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.subject ?? 'Register'),
        bottom: session == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${session.section} · started ${_clock.format(session.openedAt)}'
                    '${session.closedAt == null ? '' : ' · ended ${_clock.format(session.closedAt!)}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: rollAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The register could not be loaded: $err',
                textAlign: TextAlign.center),
          ),
        ),
        data: (marks) => Column(
          children: [
            _Summary(counts: counts),
            if (marks.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nobody is enrolled in this section yet, so there is no '
                      'register to take. The registrar assigns students to '
                      'sections.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: marks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _RollRow(
                    sessionId: sessionId,
                    mark: marks[i],
                    // A closed session from an earlier day cannot be
                    // changed -- the callable refuses it -- so the
                    // buttons say so rather than failing on tap.
                    editable: session != null && _isToday(session.date),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: session == null || !session.isOpen
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _timeOut(context, ref),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Time out'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
    );
  }

  static bool _isToday(String dateKey) {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return dateKey == '${now.year}-$month-$day';
  }
}

class _Summary extends StatelessWidget {
  final RollCounts counts;
  const _Summary({required this.counts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Wrap(
        spacing: 20,
        runSpacing: 6,
        children: [
          _Figure(label: 'Present', value: counts.present),
          _Figure(label: 'Late', value: counts.late),
          _Figure(label: 'Absent', value: counts.absent),
          _Figure(label: 'Excused', value: counts.excused),
          _Figure(label: 'On the roll', value: counts.total),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final int value;
  const _Figure({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _RollRow extends ConsumerWidget {
  final String sessionId;
  final SubjectAttendanceMark mark;
  final bool editable;

  const _RollRow({
    required this.sessionId,
    required this.mark,
    required this.editable,
  });

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    AttendanceStatus status,
  ) async {
    final controller = ref.read(classSessionActionControllerProvider.notifier);
    final ok = await controller.mark(
      sessionId: sessionId,
      studentId: mark.studentId,
      status: status,
    );
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(controller.errorMessage ?? 'That mark could not be saved.'),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mark.studentName, style: theme.textTheme.bodyLarge),
                if (mark.wasThere && mark.timeIn != null)
                  Text(
                    mark.timeOut == null
                        ? 'In ${_clock.format(mark.timeIn!)}'
                        : 'In ${_clock.format(mark.timeIn!)} · '
                            'out ${_clock.format(mark.timeOut!)}'
                            '${mark.minutes == null ? '' : ' · ${mark.minutes} min'}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          // A segmented control rather than a dropdown: four options, and
          // the whole job is one tap per exception. A dropdown makes it
          // three taps each and forty students slow.
          SegmentedButton<AttendanceStatus>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
            ),
            segments: const [
              ButtonSegment(
                value: AttendanceStatus.present,
                label: Text('P'),
                tooltip: 'Present',
              ),
              ButtonSegment(
                value: AttendanceStatus.late,
                label: Text('L'),
                tooltip: 'Late',
              ),
              ButtonSegment(
                value: AttendanceStatus.absent,
                label: Text('A'),
                tooltip: 'Absent',
              ),
              ButtonSegment(
                value: AttendanceStatus.excused,
                label: Text('E'),
                tooltip: 'Excused',
              ),
            ],
            selected: {mark.status},
            onSelectionChanged: editable
                ? (selected) => _set(context, ref, selected.first)
                : null,
          ),
        ],
      ),
    );
  }
}
