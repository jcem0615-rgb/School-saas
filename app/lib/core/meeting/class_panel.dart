import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hands.dart';

/// The class, as the teacher sees it while the lesson runs.
///
/// A grid of sixty tiles answers "is everybody here" badly and "who has
/// their hand up" not at all -- a raised hand is a small badge on one
/// square somewhere in a scrolling wall of faces, and the order they
/// went up in is invisible. So the same information gets a list: hands
/// first and in the order they were raised, then everybody else by
/// name.
///
/// It also answers the question a video grid never could: who arrived,
/// and when. A child who joined twenty minutes into the lesson is
/// something a register should show, and a tile that looks exactly like
/// everybody else's does not show it.
class ClassPanel extends StatelessWidget {
  final ValueListenable<List<Attendee>> attendees;

  /// The lesson's own clock, so a reaction fades and a wait counts up
  /// without this panel keeping a timer of its own.
  final ValueListenable<DateTime> now;

  /// Only the teacher may take a hand down for somebody.
  final bool canLowerHands;
  final void Function(String identity) onLower;
  final VoidCallback onLowerAll;

  const ClassPanel({
    super.key,
    required this.attendees,
    required this.now,
    required this.canLowerHands,
    required this.onLower,
    required this.onLowerAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<Attendee>>(
      valueListenable: attendees,
      builder: (context, everyone, _) {
        final hands = [for (final a in everyone) if (a.signal.handIsUp) a];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'In this class · ${everyone.length}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (canLowerHands && hands.isNotEmpty)
                      TextButton.icon(
                        onPressed: onLowerAll,
                        icon: const Icon(Icons.back_hand_outlined, size: 18),
                        label: Text('Lower ${hands.length}'),
                      ),
                  ],
                ),
                if (hands.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      // The order is the point. Without it the teacher
                      // calls on whoever the grid happened to draw
                      // first, which is a lottery a quiet child always
                      // loses.
                      '${hands.length} hand${hands.length == 1 ? '' : 's'} up, '
                      'in the order they were raised',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Flexible(
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: now,
                    builder: (context, tick, _) => ListView.separated(
                      shrinkWrap: true,
                      itemCount: everyone.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _Row(
                        attendee: everyone[i],
                        now: tick,
                        canLower: canLowerHands,
                        onLower: onLower,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final Attendee attendee;
  final DateTime now;
  final bool canLower;
  final void Function(String identity) onLower;

  const _Row({
    required this.attendee,
    required this.now,
    required this.canLower,
    required this.onLower,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised = attendee.signal.handRaisedAt;
    final showing = reactionIsFresh(attendee.signal, now);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: raised != null
          ? CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Text('\u{270B}'),
            )
          : CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                attendee.speaking ? Icons.graphic_eq : Icons.person_outline,
                size: 18,
                color: attendee.speaking
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              attendee.isMe ? '${attendee.name} (you)' : attendee.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showing) ...[
            const SizedBox(width: 6),
            Text(attendee.signal.reaction!.glyph),
          ],
          if (attendee.sharingScreen) ...[
            const SizedBox(width: 6),
            Icon(Icons.screen_share_outlined,
                size: 16, color: theme.colorScheme.primary),
          ],
        ],
      ),
      subtitle: Text(
        raised != null
            ? 'Hand up · ${waitingFor(now.difference(raised))}'
            // Not "present": a child who joined twenty minutes late is
            // a thing a register should show.
            : 'Joined ${_joined(attendee.joinedAt, now)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attendee.micOn ? Icons.mic : Icons.mic_off,
            size: 16,
            color: attendee.micOn
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Icon(
            attendee.cameraOn ? Icons.videocam : Icons.videocam_off,
            size: 16,
            color: attendee.cameraOn
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outline,
          ),
          if (canLower && raised != null)
            TextButton(
              onPressed: () => onLower(attendee.identity),
              child: const Text('Lower'),
            ),
        ],
      ),
    );
  }

  String _joined(DateTime at, DateTime now) {
    final ago = now.difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inMinutes == 1) return '1 min ago';
    return '${ago.inMinutes} min ago';
  }
}
