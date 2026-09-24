import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/meeting/online_class_screen.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';

/// "Mathematics is on now." The way into a lesson being held online.
///
/// Renders nothing at all when there is no live class, which is almost
/// always -- a banner that is usually an empty box with a heading is
/// worse than no banner, because it trains people not to look at it.
///
/// A student gets the way in from their own line in the register, not
/// from the session: `classSessions` is staff-only, and it stays that
/// way. Nothing about holding a class online widened a rule.
class LiveOnlineClassBanner extends ConsumerWidget {
  final String studentId;

  const LiveOnlineClassBanner({super.key, required this.studentId});

  /// Goes in, having first asked LogicClass for the pass.
  ///
  /// The child is already signed in -- to this app -- so the video call
  /// is told who they are rather than asking them. Without this a pupil
  /// meets a sign-in page belonging to a company they have no account
  /// with, on the way into their own school's lesson.
  ///
  /// One method for both the card and the Join button: they were two
  /// copies of the same push, and a second copy is where a fix like
  /// this one gets applied to one of them.
  Future<void> _join(
    BuildContext context,
    WidgetRef ref,
    SubjectAttendanceMark mark,
    String displayName,
  ) async {
    final pass = await ref
        .read(classSessionActionControllerProvider.notifier)
        .meetingToken(mark.sessionId);
    if (!context.mounted) return;
    if (!pass.allowed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(pass.refusal ?? 'You could not be let into the class.'),
        ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineClassScreen(
        room: mark.meetingRoom!,
        subject: mark.subject,
        section: mark.section,
        // Their real name. A register that has to match faces to names
        // cannot do it against a grid of nicknames.
        displayName: displayName,
        token: pass.token,
        // When the lesson started, from their own mark. The timetabled
        // length is not on it, so a student sees time elapsed and no
        // countdown -- the bell is the teacher's to keep.
        openedAt: mark.timeIn,
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = ref.watch(myOnlineClassProvider(studentId));
    if (mark == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final me = ref.watch(authStateProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              _join(context, ref, mark, me?.fullName ?? mark.studentName),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.videocam, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${mark.subject} is online now',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Your teacher has started the class.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      _join(context, ref, mark, me?.fullName ?? mark.studentName),
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
