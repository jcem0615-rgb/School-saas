import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../controllers/class_session_controller.dart';
import '../widgets/join_online_class.dart';

/// Where a student goes to get into a lesson.
///
/// ## Why this exists when there is already a banner and a link
///
/// The banner only appears while a class is on, which is most of the
/// time not. A student who has been told "we are online today" and sees
/// nothing on their dashboard has no way of knowing whether the lesson
/// has not started or whether the app has lost it -- and nowhere to
/// look. A tile that is always there answers that: open it and it
/// either lists the lesson or says, in a sentence, that nothing has
/// started yet.
///
/// The invitation link lands people here too, in the sense that it lands
/// them in this app. A link is a convenience for somebody who has one;
/// it is not the way into the school's own lesson, and a pupil whose
/// chat app mangled the link needs a door that does not depend on it.
///
/// Nothing here decides anything. The way in is still the student's own
/// line in the register, and the pass is still minted by the server
/// after it has checked the register, the code and the scope.
class MyOnlineClassesScreen extends ConsumerWidget {
  final String studentId;

  const MyOnlineClassesScreen({super.key, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final live = ref.watch(myOnlineClassesProvider(studentId));
    final me = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Online Class')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (live.isEmpty)
            _NothingOnNow(theme: theme)
          else ...[
            Text(
              live.length == 1
                  ? 'One class is on now.'
                  : '${live.length} classes are on now.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Your teacher will read out the class code at the start.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final mark in live)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.videocam,
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: Text(
                    mark.subject.isEmpty ? 'Class' : mark.subject,
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    mark.section.isEmpty
                        ? 'Your teacher has started the class.'
                        : '${mark.section} · your teacher has started the class.',
                  ),
                  trailing: FilledButton(
                    onPressed: () => joinOnlineClass(
                      context,
                      ref,
                      mark,
                      me?.fullName ?? mark.studentName,
                    ),
                    child: const Text('Join'),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          _HowItWorks(theme: theme),
        ],
      ),
    );
  }
}

class _NothingOnNow extends StatelessWidget {
  final ThemeData theme;
  const _NothingOnNow({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.videocam_off_outlined,
            size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text('No class is online right now',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          // The sentence this screen exists for. "Nothing here" is what
          // a broken app looks like too; saying which of the two it is
          // costs one line.
          'A lesson appears here the moment your teacher takes it online. '
          'It will also show on your dashboard while it is running.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  final ThemeData theme;
  const _HowItWorks({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('If your teacher sent you a link',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            // Worth saying plainly, because a link that opens the app on
            // the sign-in page looks broken to a twelve-year-old who
            // expected a video call.
            'Opening it brings you here and asks you to sign in first. You '
            'do not need the link — any class you are on the register for '
            'appears on this screen while it is running.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
