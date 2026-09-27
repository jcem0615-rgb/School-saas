import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// How many tiles fit across, for a given number of people and width.
///
/// Pure, and separate from the widget, because the arithmetic is the
/// part that goes wrong and a class of sixty is not something anybody
/// will check by eye. Roughly square: a grid that is six wide and two
/// tall wastes half a screen on a phone and crushes faces on a desktop.
int gridColumnsFor({required int tiles, required double width}) {
  if (tiles <= 1) return 1;
  // What the screen can carry before faces stop being faces. 180px is
  // about the width a person is still recognisable at, which is the
  // whole purpose of a class being on camera.
  final affordable = (width / 180).floor().clamp(1, 8);
  // Square-ish, then capped by the screen.
  final square = (tiles <= 2) ? 2 : (tiles <= 6 ? 3 : (tiles <= 12 ? 4 : 6));
  return square < affordable ? square : affordable;
}

/// Everybody in the lesson, drawn by this app.
///
/// Flutter widgets over video tracks. No iframe, no third-party page,
/// nothing that can decline to be embedded -- which is the whole reason
/// this exists rather than an embedded meeting from somebody else.
class VideoGrid extends StatefulWidget {
  final lk.Room room;
  const VideoGrid({super.key, required this.room});

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  @override
  void initState() {
    super.initState();
    // The room is a ChangeNotifier: people arriving and leaving, tracks
    // published and muted. Listened to here and nowhere above, so a
    // participant joining never rebuilds the screen around the call.
    widget.room.addListener(_changed);
  }

  @override
  void dispose() {
    widget.room.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <_Tile>[
      if (widget.room.localParticipant != null)
        _Tile(widget.room.localParticipant!, isMe: true),
      for (final other in widget.room.remoteParticipants.values)
        _Tile(other, isMe: false),
    ];

    if (tiles.isEmpty) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text('Waiting for the class to arrive',
              style: theme.textTheme.bodyMedium),
        ),
      );
    }

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, box) => GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                gridColumnsFor(tiles: tiles.length, width: box.maxWidth),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4 / 3,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, i) => _ParticipantTile(tile: tiles[i]),
        ),
      ),
    );
  }
}

class _Tile {
  final lk.Participant participant;
  final bool isMe;
  const _Tile(this.participant, {required this.isMe});
}

class _ParticipantTile extends StatelessWidget {
  final _Tile tile;
  const _ParticipantTile({required this.tile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = tile.participant.videoTrackPublications
        .where((p) => p.subscribed && !p.muted && p.track != null)
        .map((p) => p.track)
        .whereType<lk.VideoTrack>()
        .firstOrNull;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              lk.VideoTrackRenderer(video, fit: lk.VideoViewFit.cover)
            else
              // A camera that is off is a name, not a black hole. In a
              // lesson the register is the point, so who is present
              // must read even when nobody can be seen.
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    tile.participant.name.isEmpty
                        ? tile.participant.identity
                        : tile.participant.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    tile.isMe ? 'You' : tile.participant.name,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
