import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../board_controller.dart';
import '../whiteboard.dart';
import 'stage.dart';

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

/// The shape of the tile a teacher draws on.
///
/// Sixteen by nine, forced, on every device. This is what makes the
/// marks land in the right place: a mark is a fraction of the tile, so
/// two devices agree about where it goes only if their tiles are the
/// same shape. Let the tile take the shape of the window and a circle
/// drawn round a figure on a laptop lands in the margin on a phone.
///
/// A screen share that is not 16:9 letterboxes inside the box -- by the
/// same amount, on every device, because the box and the picture are
/// the same shape everywhere. So the marks still line up.
const spotlightAspect = 16 / 9;

/// Everybody in the lesson, drawn by this app.
///
/// Flutter widgets over video tracks. No iframe, no third-party page,
/// nothing that can decline to be embedded -- which is the whole reason
/// this exists rather than an embedded meeting from somebody else.
class VideoGrid extends StatefulWidget {
  final lk.Room room;

  /// What the teacher has drawn, when there is a board in this lesson.
  final LessonBoard? board;

  const VideoGrid({super.key, required this.room, this.board});

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
    final participants = <lk.Participant>[
      if (widget.room.localParticipant != null) widget.room.localParticipant!,
      ...widget.room.remoteParticipants.values,
    ];

    if (participants.isEmpty) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text('Waiting for the class to arrive',
              style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final me = widget.room.localParticipant;
    final stage = stageFor([
      for (final one in participants)
        StageSeat(
          id: one.identity,
          isMe: identical(one, me),
          sharingScreen: _screenOf(one) != null,
        ),
    ]);
    final byId = {for (final one in participants) one.identity: one};

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: stage.isGrid
          ? _Grid(participants: participants, me: me)
          : _Spotlight(
              sharer: byId[stage.spotlight!.id]!,
              strip: [for (final seat in stage.strip) byId[seat.id]!],
              me: me,
              board: widget.board,
            ),
    );
  }
}

lk.VideoTrack? _screenOf(lk.Participant participant) => participant
    .getTrackPublicationBySource(lk.TrackSource.screenShareVideo)
    ?.track as lk.VideoTrack?;

class _Grid extends StatelessWidget {
  final List<lk.Participant> participants;
  final lk.Participant? me;
  const _Grid({required this.participants, required this.me});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                gridColumnsFor(tiles: participants.length, width: box.maxWidth),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4 / 3,
          ),
          itemCount: participants.length,
          itemBuilder: (context, i) => ParticipantTile(
            participant: participants[i],
            isMe: identical(participants[i], me),
          ),
        ),
      );
}

/// A shared window in the middle, with the class along one edge.
class _Spotlight extends StatelessWidget {
  final lk.Participant sharer;
  final List<lk.Participant> strip;
  final lk.Participant? me;
  final LessonBoard? board;

  const _Spotlight({
    required this.sharer,
    required this.strip,
    required this.me,
    required this.board,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final beside = stripBesideSpotlight(
            width: box.maxWidth,
            height: box.maxHeight,
          );
          final extent = stripExtentFor(
            box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight,
          );
          final faces = SizedBox(
            width: beside ? extent : null,
            height: beside ? null : extent,
            child: ListView.separated(
              scrollDirection: beside ? Axis.vertical : Axis.horizontal,
              padding: const EdgeInsets.all(8),
              itemCount: strip.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8, height: 8),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 4 / 3,
                child: ParticipantTile(
                  participant: strip[i],
                  isMe: identical(strip[i], me),
                ),
              ),
            ),
          );
          final shared = Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: AspectRatio(
                aspectRatio: spotlightAspect,
                child: _SharedScreen(sharer: sharer, board: board),
              ),
            ),
          );

          return beside
              ? Row(children: [Expanded(child: shared), faces])
              : Column(children: [Expanded(child: shared), faces]);
        },
      );
}

class _SharedScreen extends StatelessWidget {
  final lk.Participant sharer;
  final LessonBoard? board;
  const _SharedScreen({required this.sharer, required this.board});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = _screenOf(sharer);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: theme.colorScheme.scrim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (screen != null)
              // Contained, never cropped. A shared spreadsheet with its
              // last column cut off is a shared spreadsheet that has
              // failed at the one thing it was shared for.
              lk.VideoTrackRenderer(screen, fit: lk.VideoViewFit.contain),
            if (board != null) BoardLayer(board: board!),
          ],
        ),
      ),
    );
  }
}

/// What the teacher has drawn, over the thing being discussed.
///
/// Coordinates are fractions of this layer, and this layer is the same
/// shape on every device, which is the whole of why a circle drawn on a
/// laptop lands round the same word on a phone.
class BoardLayer extends StatefulWidget {
  final LessonBoard board;
  const BoardLayer({super.key, required this.board});

  @override
  State<BoardLayer> createState() => _BoardLayerState();
}

class _BoardLayerState extends State<BoardLayer> {
  @override
  void initState() {
    super.initState();
    widget.board.addListener(_changed);
  }

  @override
  void didUpdateWidget(BoardLayer old) {
    super.didUpdateWidget(old);
    if (old.board != widget.board) {
      old.board.removeListener(_changed);
      widget.board.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.board.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          Offset at(Offset local) => Offset(
                (local.dx / box.maxWidth).clamp(0.0, 1.0),
                (local.dy / box.maxHeight).clamp(0.0, 1.0),
              );

          return IgnorePointer(
            // A lesson spends almost all of its time with no tool in
            // hand, and the shared screen underneath must stay reachable.
            ignoring: widget.board.tool == BoardTool.off,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => widget.board.startAt(at(d.localPosition)),
              onPanUpdate: (d) => widget.board.extendTo(at(d.localPosition)),
              onPanEnd: (_) => widget.board.finish(),
              onPanCancel: widget.board.finish,
              child: CustomPaint(
                painter: _BoardPainter(
                  board: widget.board.board,
                  drawing: widget.board.drawing,
                  colour: widget.board.colour,
                ),
                size: Size.infinite,
              ),
            ),
          );
        },
      );
}

class _BoardPainter extends CustomPainter {
  final Whiteboard board;
  final List<Offset>? drawing;
  final int colour;

  const _BoardPainter({
    required this.board,
    required this.drawing,
    required this.colour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in board.marks) {
      _stroke(canvas, size, mark.points, mark.colour, mark.width);
    }
    final live = drawing;
    if (live != null && live.isNotEmpty) {
      _stroke(canvas, size, live, colour, LessonBoard.pencilWidth);
    }
  }

  void _stroke(
    Canvas canvas,
    Size size,
    List<Offset> points,
    int colour,
    double width,
  ) {
    final brush = Paint()
      ..color = Color(colour)
      ..style = PaintingStyle.stroke
      // Width is a fraction of the tile too, so a line keeps its weight
      // relative to what it was drawn on.
      ..strokeWidth = (width * size.width).clamp(1.5, 24.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    Offset on(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    path.moveTo(on(points.first).dx, on(points.first).dy);
    for (final point in points.skip(1)) {
      path.lineTo(on(point).dx, on(point).dy);
    }
    canvas.drawPath(path, brush);
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      !identical(old.board, board) ||
      old.drawing?.length != drawing?.length ||
      old.colour != colour;
}

class ParticipantTile extends StatelessWidget {
  final lk.Participant participant;
  final bool isMe;

  const ParticipantTile({
    super.key,
    required this.participant,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = participant.videoTrackPublications
        .where((p) => p.subscribed && !p.muted && p.track != null)
        .where((p) => p.source != lk.TrackSource.screenShareVideo)
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
                    participant.name.isEmpty
                        ? participant.identity
                        : participant.name,
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
                    isMe ? 'You' : participant.name,
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
