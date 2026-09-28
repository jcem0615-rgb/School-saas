/// What a teacher draws on the lesson, and how it reaches everybody.
///
/// Marking up the thing under discussion is the oldest teaching move
/// there is -- a finger on a diagram, a circle round the term that
/// matters. On a shared screen it is the difference between "look at
/// the third column" and pointing at the third column.
///
/// Two decisions hold this together.
///
/// **Coordinates are fractions of the tile, never pixels.** The teacher
/// draws on a laptop and a pupil watches on a phone held sideways; a
/// mark at (0.31, 0.62) is over the same word on both. A mark at
/// (412, 780) is over the same word on neither.
///
/// **A stroke travels once, when it is finished.** Sending every touch
/// as it happens is sixty packets a second to sixty people, and the
/// difference is invisible: a stroke that lands a quarter of a second
/// late is still landing while the teacher is still talking about it.
/// The person drawing sees their own line immediately, from their own
/// hand, and is the only one who would notice.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A single stroke of the pencil.
class Mark {
  /// Made where the stroke was made, so an erasure can name it.
  ///
  /// Erasing broadcasts the ids it removed rather than the shape of the
  /// rubber, because "remove these three" lands identically on every
  /// device and "rub here, this hard" does not.
  final String id;

  /// ARGB, chosen from a short list. Whatever the teacher picked has to
  /// read against a slide that might be white or might be a photograph.
  final int colour;

  /// A fraction of the tile's width, like the coordinates, so the line
  /// keeps its weight relative to what it is drawn on.
  final double width;

  /// In fractions of the tile, 0..1 from its top left.
  final List<Offset> points;

  const Mark({
    required this.id,
    required this.colour,
    required this.width,
    required this.points,
  });

  /// How far this stroke is from a point, in tile fractions.
  ///
  /// Distance to the nearest segment, not to the nearest recorded
  /// point: a long straight line has two points a third of the tile
  /// apart, and a rubber held against the middle of it must find it.
  double distanceTo(Offset point) {
    if (points.isEmpty) return double.infinity;
    if (points.length == 1) return (points.first - point).distance;
    var nearest = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final d = _distanceToSegment(point, points[i], points[i + 1]);
      if (d < nearest) nearest = d;
    }
    return nearest;
  }

  Map<String, dynamic> toJson() => {
        'i': id,
        'c': colour,
        'w': _round(width),
        // Flat, and rounded to four places. A fraction of a tile at
        // four places is a fifth of a pixel on a 4K screen, and the
        // packet is half the size of the same numbers written out.
        'p': [
          for (final p in points) ...[_round(p.dx), _round(p.dy)]
        ],
      };

  static Mark? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['i'];
    final colour = value['c'];
    final width = value['w'];
    final flat = value['p'];
    if (id is! String || colour is! num || width is! num || flat is! List) {
      return null;
    }
    final points = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final x = flat[i];
      final y = flat[i + 1];
      if (x is! num || y is! num) return null;
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    if (points.isEmpty) return null;
    return Mark(
      id: id,
      colour: colour.toInt(),
      width: width.toDouble(),
      points: points,
    );
  }
}

/// Everything drawn on the lesson so far.
///
/// Immutable, and replaced rather than mutated, so a repaint cannot
/// catch it half-changed and so the strokes arriving over the network
/// and the strokes coming from the hand holding the device go through
/// exactly the same door.
class Whiteboard {
  final List<Mark> marks;

  const Whiteboard([this.marks = const []]);

  bool get isEmpty => marks.isEmpty;
  bool get isNotEmpty => marks.isNotEmpty;

  /// The oldest strokes fall off the end.
  ///
  /// A board nobody ever clears is a lesson that gets slower as it goes
  /// on, and the marks from forty minutes ago are not being looked at.
  static const limit = 400;

  Whiteboard add(Mark mark) {
    final next = [...marks.where((m) => m.id != mark.id), mark];
    return Whiteboard(
      next.length <= limit ? next : next.sublist(next.length - limit),
    );
  }

  Whiteboard remove(Iterable<String> ids) {
    final gone = ids.toSet();
    if (gone.isEmpty) return this;
    return Whiteboard([...marks.where((m) => !gone.contains(m.id))]);
  }

  Whiteboard get cleared => const Whiteboard();

  /// Which strokes the rubber is touching, at this position and size.
  List<String> hits(Offset point, double radius) => [
        for (final mark in marks)
          if (mark.distanceTo(point) <= radius + mark.width / 2) mark.id,
      ];
}

/// What one message on the wire means.
sealed class BoardMessage {
  const BoardMessage();
}

/// One finished stroke.
class MarkDrawn extends BoardMessage {
  final Mark mark;
  const MarkDrawn(this.mark);
}

/// Strokes the rubber took out, by id.
class MarksErased extends BoardMessage {
  final List<String> ids;
  const MarksErased(this.ids);
}

/// The board, wiped.
class BoardCleared extends BoardMessage {
  const BoardCleared();
}

/// The whole board at once.
///
/// Sent to somebody who has just arrived. A pupil who joins ten minutes
/// in otherwise sees a clean slide with the teacher talking about a
/// circle that is not there.
class BoardReplaced extends BoardMessage {
  final Whiteboard board;
  const BoardReplaced(this.board);
}

String encodeBoardMessage(BoardMessage message) => jsonEncode(switch (message) {
      MarkDrawn(:final mark) => {'t': 'm', 'm': mark.toJson()},
      MarksErased(:final ids) => {'t': 'e', 'e': ids},
      BoardCleared() => {'t': 'c'},
      BoardReplaced(:final board) => {
          't': 'f',
          'f': [for (final mark in board.marks) mark.toJson()],
        },
    });

/// Reads a message, or returns null.
///
/// Null for anything unrecognised rather than an exception. This
/// arrives from the network during a lesson, and a version of the app
/// that sends a message this one has never heard of must be ignored,
/// not allowed to end the class.
BoardMessage? decodeBoardMessage(String text) {
  try {
    final value = jsonDecode(text);
    if (value is! Map) return null;
    switch (value['t']) {
      case 'm':
        final mark = Mark.fromJson(value['m']);
        return mark == null ? null : MarkDrawn(mark);
      case 'e':
        final ids = value['e'];
        if (ids is! List) return null;
        return MarksErased([...ids.whereType<String>()]);
      case 'c':
        return const BoardCleared();
      case 'f':
        final all = value['f'];
        if (all is! List) return null;
        final marks = [
          for (final one in all)
            if (Mark.fromJson(one) case final mark?) mark,
        ];
        return BoardReplaced(Whiteboard(marks));
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// The board after a message has been applied to it.
Whiteboard applyBoardMessage(Whiteboard board, BoardMessage message) =>
    switch (message) {
      MarkDrawn(:final mark) => board.add(mark),
      MarksErased(:final ids) => board.remove(ids),
      BoardCleared() => board.cleared,
      BoardReplaced(:final board) => board,
    };

/// Drops points too close together to be seen.
///
/// A finger dragged slowly puts hundreds of points inside a centimetre.
/// They cost packet size and draw nothing, and LiveKit will not carry a
/// message past about fifteen kilobytes -- which a single unthinned
/// stroke can reach.
List<Offset> thinned(List<Offset> points, {double minStep = 0.004}) {
  if (points.length <= 2) return points;
  final kept = <Offset>[points.first];
  for (final point in points.skip(1)) {
    if ((point - kept.last).distance >= minStep) kept.add(point);
  }
  // The last point is where the hand stopped, which is where the line
  // should stop.
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}

double _round(double value) => (value * 10000).roundToDouble() / 10000;

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return (point - a).distance;
  final t =
      (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / lengthSquared)
          .clamp(0.0, 1.0);
  return (point - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
}

/// A stroke id that two devices cannot both invent.
String newMarkId(math.Random random) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final id = StringBuffer();
  for (var i = 0; i < 10; i++) {
    id.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return id.toString();
}
