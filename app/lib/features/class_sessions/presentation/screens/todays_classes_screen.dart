import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/meeting/invite_link.dart';
import '../../../../core/meeting/online_class_screen.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../../schedules/domain/entities/schedule_block.dart';
import '../../../schedules/presentation/controllers/schedule_controller.dart'
    show teacherScheduleProvider;
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';
import 'class_roll_screen.dart';

final _clock = DateFormat('h:mm a');

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Start teaching this class online, from wherever it currently is.
///
/// One call rather than four steps. A lesson cannot be held online
/// without a register -- the room is stamped onto each student's mark,
/// which is how they reach it -- so this opens the session if it is not
/// open, takes it online if it is not online, collects the pass and goes
/// in. The teacher who has just been told classes are suspended should
/// not have to know that order.
///
/// [unscheduled] carries through to the server, which otherwise refuses
/// a class the timetable does not put today.
Future<void> startOnlineClass({
  required BuildContext context,
  required WidgetRef ref,
  required ScheduleBlock block,
  ClassSession? existing,
  bool unscheduled = false,
}) async {
  final controller = ref.read(classSessionActionControllerProvider.notifier);

  var sessionId = existing?.id;
  if (sessionId == null) {
    sessionId = await controller.openSession(block.id, unscheduled: unscheduled);
    if (!context.mounted) return;
    if (sessionId == null) {
      _say(context, controller.errorMessage ?? 'The class could not be started.');
      return;
    }
  }

  // Already online: go straight in rather than opening a second room,
  // which would strand anybody already waiting in the first.
  var room = existing?.meetingRoom;
  var passcode = existing?.meetingPasscode;
  if (room == null || room.isEmpty) {
    final setup = await controller.setMode(sessionId: sessionId, online: true);
    if (!context.mounted) return;
    if (setup == null || !setup.isOnline) {
      _say(context, controller.errorMessage ?? 'The class could not be moved online.');
      return;
    }
    room = setup.room;
    passcode = setup.passcode;
  }

  // The pass, so the lesson does not open onto a sign-in page.
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
      provider: pass.provider,
      serverUrl: pass.url,
      asModerator: true,
      openedAt: existing?.openedAt ?? DateTime.now(),
      // Safe to forward; the code is not in it, and is read out.
      inviteLink: classInviteLink(
        schoolId: me?.schoolId,
        sessionId: sessionId!,
      ),
      passcode: passcode,
    ),
  ));
}

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
      appBar: AppBar(
        title: const Text('My classes today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Hold an online class',
            onPressed: () => _pickAClass(context, ref),
          ),
        ],
      ),
      body: classes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // Two different reasons for an empty list, and a
                      // teacher can tell them apart: a Saturday is
                      // obvious, a missing timetable is the office's to
                      // fix.
                      'Nothing on your timetable for '
                      '${weekdayLabel(DateTime.now().weekday)}. If that is wrong, '
                      'the office keeps the timetable.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    // The timetable is not the whole of a school year.
                    // A make-up lesson for the day a typhoon closed the
                    // school, a review session on the Sunday before an
                    // exam -- a teacher who needs one of those was
                    // being told to go away by a screen that had no
                    // other button on it.
                    FilledButton.icon(
                      onPressed: () => _pickAClass(context, ref),
                      icon: const Icon(Icons.videocam, size: 18),
                      label: const Text('Hold an online class anyway'),
                    ),
                  ],
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

/// Pick any class this teacher takes and hold it online now.
///
/// The day's list is the ordinary way in and stays the ordinary way in.
/// This is the other one, and it exists because a timetable describes an
/// ordinary week rather than a school year: the lessons that most need
/// to be held online -- the make-up for the day a typhoon closed the
/// school, the review session before an exam, the class moved because
/// the hall was needed -- are exactly the ones no timetable has a row
/// for. A teacher meeting "nothing on your timetable for Sunday" with no
/// other button on the screen has been told the feature is unavailable
/// on the days it is most wanted.
Future<void> _pickAClass(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) return;

  // Every class this teacher takes, one row per subject and section --
  // the same subject four times over in a week is four rows on a
  // timetable and one decision here.
  final week = ref.read(teacherScheduleProvider(uid));
  final seen = <String>{};
  final choices = <ScheduleBlock>[];
  for (final block in week) {
    if (seen.add('${block.subject}|${block.section}')) choices.add(block);
  }
  choices.sort((a, b) {
    final bySubject = a.subject.compareTo(b.subject);
    return bySubject != 0 ? bySubject : a.section.compareTo(b.section);
  });

  if (choices.isEmpty) {
    _say(context, 'You have no classes on the timetable yet. The office keeps it.');
    return;
  }

  final today = DateTime.now().weekday;
  final picked = await showModalBottomSheet<ScheduleBlock>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Hold an online class',
                  style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'The register opens today, whatever day the timetable '
                'gives the class.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final block in choices)
                    ListTile(
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(block.subject),
                      subtitle: Text(
                        block.dayOfWeek == today
                            ? '${block.section} · on today\'s timetable'
                            : '${block.section} · usually ${weekdayLabel(block.dayOfWeek)}',
                      ),
                      onTap: () => Navigator.of(sheet).pop(block),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (picked == null || !context.mounted) return;
  await startOnlineClass(
    context: context,
    ref: ref,
    block: picked,
    // Only when it really is off the timetable. A class picked here on
    // its own day is an ordinary register and is recorded as one.
    unscheduled: picked.dayOfWeek != DateTime.now().weekday,
  );
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
                      onPressed: busy
                          ? null
                          : () => startOnlineClass(
                                context: context,
                                ref: ref,
                                block: block,
                                existing: session,
                              ),
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
