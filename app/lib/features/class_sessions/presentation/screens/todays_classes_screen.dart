import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/meeting/online_class_screen.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../../schedules/domain/entities/schedule_block.dart';
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';
import 'class_roll_screen.dart';

final _clock = DateFormat('h:mm a');

/// The teacher's day, with a Time In on each class.
///
/// The school already knew whether a student came in through the gate.
/// It did not know whether they were in Physics -- which is the thing a
/// subject teacher, a failing grade and a worried parent are all
/// actually asking about. So each timetabled class gets a session: Time
/// In at the start, Time Out at the end, and a register in between.
class TodaysClassesScreen extends ConsumerWidget {
  const TodaysClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(myClassesTodayProvider);
    // Watched for its side effect: the subscription is what makes each
    // card's "in progress" state live. There is no spinner for it --
    // the classes themselves come from the timetable, which is already
    // loaded, and an indeterminate bar over a list that is already there
    // reads as a screen that is not ready when it is.
    ref.watch(todaysSessionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('My classes today')),
      body: classes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  // Two different reasons for an empty list, and a
                  // teacher can tell them apart: a Saturday is obvious,
                  // a missing timetable is the office's to fix.
                  'Nothing on your timetable for '
                  '${weekdayLabel(DateTime.now().weekday)}. If that is wrong, '
                  'the office keeps the timetable.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final block in classes)
                  _ClassCard(block: block),
              ],
            ),
    );
  }
}

class _ClassCard extends ConsumerWidget {
  final ScheduleBlock block;
  const _ClassCard({required this.block});

  Future<void> _timeIn(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(classSessionActionControllerProvider.notifier);
    final sessionId = await controller.openSession(block.id);
    if (!context.mounted) return;
    if (sessionId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(controller.errorMessage ?? 'The class could not be started.'),
        ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClassRollScreen(sessionId: sessionId),
    ));
  }

  /// Start teaching this class online, from wherever it currently is.
  ///
  /// One button rather than three steps. A lesson cannot be held online
  /// without a register -- the room is stamped onto each student's mark,
  /// which is how they reach it -- so this opens the session if it is
  /// not open, takes it online if it is not online, and goes in. The
  /// teacher who has just been told classes are suspended should not
  /// have to know that order.
  Future<void> _startOnline(
    BuildContext context,
    WidgetRef ref,
    ClassSession? existing,
  ) async {
    final controller = ref.read(classSessionActionControllerProvider.notifier);

    var sessionId = existing?.id;
    if (sessionId == null) {
      sessionId = await controller.openSession(block.id);
      if (!context.mounted) return;
      if (sessionId == null) {
        _say(context, controller.errorMessage ?? 'The class could not be started.');
        return;
      }
    }

    // Already online: go straight in rather than opening a second room,
    // which would strand anybody already waiting in the first.
    var room = existing?.meetingRoom;
    if (room == null || room.isEmpty) {
      room = await controller.setMode(sessionId: sessionId, online: true);
      if (!context.mounted) return;
      if (room == null) {
        _say(context, controller.errorMessage ?? 'The class could not be moved online.');
        return;
      }
    }

    // The pass, so the lesson does not open onto a sign-in page. The
    // teacher signed in to LogicClass; asking them to hold a Google
    // account as well to teach their own class is the thing this
    // removes.
    final pass = await controller.meetingToken(sessionId);
    if (!context.mounted) return;
    if (!pass.allowed) {
      _say(context, pass.refusal ?? 'You could not be let into the class.');
      return;
    }

    final me = ref.read(authStateProvider).valueOrNull;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineClassScreen(
        room: room!,
        subject: block.subject,
        section: block.section,
        displayName: me?.fullName ?? 'Teacher',
        token: pass.token,
        asModerator: true,
        openedAt: existing?.openedAt ?? DateTime.now(),
        scheduledMinutes: block.durationMinutes,
      ),
    ));
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionForBlockProvider(block.id));
    final busy = ref.watch(classSessionActionControllerProvider).isLoading;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(block.subject,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${block.section} · ${block.timeLabel}'
                        '${block.room == null ? '' : ' · ${block.room}'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (session != null) _SessionChip(session: session),
              ],
            ),
            const SizedBox(height: 10),
            if (session != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Started ${_clock.format(session.openedAt)}'
                  '${session.closedAt == null ? '' : ', ended ${_clock.format(session.closedAt!)}'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            // Wrap and right-aligned: three actions and a sentence do not
            // fit one line on a phone, and the control that starts a
            // lesson is the last thing that should be clipped off a card.
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (session == null)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _timeIn(context, ref),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Time in'),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ClassRollScreen(sessionId: session.id),
                      )),
                      child: Text(session.isOpen ? 'Open register' : 'View register'),
                    ),
                  // Not offered on a class that has finished: the server
                  // refuses to open a room on a closed register, and a
                  // button whose only outcome is an error message is
                  // worse than no button.
                  if (session == null || session.isOpen)
                    FilledButton.icon(
                      onPressed: busy ? null : () => _startOnline(context, ref, session),
                      icon: const Icon(Icons.videocam, size: 18),
                      label: Text(session?.isOnlineNow == true
                          ? 'Join online class'
                          : 'Start online class'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionChip extends StatelessWidget {
  final ClassSession session;
  const _SessionChip({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = session.isOpen;
    final colour = running ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        running ? 'In progress' : 'Finished',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: colour, fontWeight: FontWeight.w700),
      ),
    );
  }
}
