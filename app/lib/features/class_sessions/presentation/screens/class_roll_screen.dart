import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../domain/entities/class_session.dart';
import '../../../../core/meeting/online_class_screen.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../../schedules/presentation/controllers/schedule_controller.dart'
    show scheduleProvider;
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
            if (session != null && session.isOpen)
              _OnlineClassBar(session: session, busy: busy),
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

/// Taking this lesson online, and the way back in.
///
/// On the register rather than the timetable because the reasons are
/// same-day ones -- a typhoon, a suspension of classes, a teacher
/// isolating -- and a school that has to edit its timetable at 6am to
/// hold a lesson will not hold the lesson.
class _OnlineClassBar extends ConsumerWidget {
  final ClassSession session;
  final bool busy;

  const _OnlineClassBar({required this.session, required this.busy});

  Future<void> _setMode(BuildContext context, WidgetRef ref, bool online) async {
    final notifier = ref.read(classSessionActionControllerProvider.notifier);
    final room = await notifier.setMode(sessionId: session.id, online: online);
    if (!context.mounted) return;

    final failed = notifier.errorMessage != null;
    if (failed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notifier.errorMessage!)));
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(online
            ? 'The class is online. Everyone on the register can join it now.'
            : 'The class is back in person and the room is closed.'),
      ));
    if (online && room != null && context.mounted) _join(context, ref, room);
  }

  void _join(BuildContext context, WidgetRef ref, String room) {
    final me = ref.read(authStateProvider).valueOrNull;
    // The timetabled length, so the classroom can show a clock. Null
    // when the block has gone -- an unknown length shows elapsed time
    // alone rather than a made-up total.
    final block = ref
        .read(scheduleProvider)
        .valueOrNull
        ?.where((b) => b.id == session.scheduleBlockId)
        .firstOrNull;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineClassScreen(
        room: room,
        subject: session.subject,
        section: session.section,
        displayName: me?.fullName ?? 'Teacher',
        // The teacher arrives un-muted and able to end it for everyone.
        asModerator: true,
        openedAt: session.openedAt,
        scheduledMinutes: block?.durationMinutes,
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final online = session.isOnlineNow;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: online
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(
          color: online
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      // The sentence above the buttons rather than beside them, and the
      // buttons in a Wrap: at phone width with a large text scale, a
      // sentence and two buttons on one line are wider than the card,
      // and the control that holds a lesson is the last thing that
      // should be clipped off the edge of it.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(online ? Icons.videocam : Icons.meeting_room_outlined,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  online
                      ? 'This class is online. Everyone on the register can join.'
                      : 'This class is in the room.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (online) ...[
                TextButton(
                  onPressed: busy ? null : () => _setMode(context, ref, false),
                  child: const Text('End'),
                ),
                FilledButton.icon(
                  onPressed:
                      busy ? null : () => _join(context, ref, session.meetingRoom!),
                  icon: const Icon(Icons.videocam, size: 18),
                  label: const Text('Join'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: busy ? null : () => _setMode(context, ref, true),
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Take online'),
                ),
            ],
          ),
        ],
      ),
    );
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
