import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'whiteboard.dart';

/// Which tool the hand is holding.
enum BoardTool {
  /// Nothing. Dragging moves nothing and draws nothing, which is what
  /// a lesson is doing almost all of the time.
  off,
  pencil,
  eraser,
}

/// The board during a lesson: what is on it, what the hand is doing,
/// and how the two reach everybody else.
///
/// A notifier rather than screen state, for the reason that has already
/// cost this module a working lesson twice: the video lives in a widget
/// that must not be rebuilt, and a stroke arrives sixty times a second
/// while it is being drawn. Everything that moves during a lesson moves
/// through one of these.
///
/// Sending is a seam. A test can hold both ends of it and prove that
/// what one device draws is what another device ends up with, which is
/// the only property of this that actually matters and the one that no
/// amount of looking at a screen will establish.
class LessonBoard extends ChangeNotifier {
  /// Puts a message on the wire. Called once per finished stroke, once
  /// per rub, once per clearing.
  final void Function(BoardMessage message) send;

  /// Only the teacher draws.
  ///
  /// Not a nicety: sixty pupils with a pencil over a shared screen is
  /// not a lesson. The tools are not offered to anybody else, and this
  /// says so a second time in case a future screen forgets.
  final bool canDraw;

  final Random _random;

  LessonBoard({required this.send, required this.canDraw, Random? random})
      : _random = random ?? Random();

  Whiteboard _board = const Whiteboard();
  Whiteboard get board => _board;

  BoardTool _tool = BoardTool.off;
  BoardTool get tool => _tool;

  /// The colours a teacher can pick between.
  ///
  /// Short on purpose. Four that read against a white slide, a dark
  /// slide and a photograph is a decision taken in a second; a colour
  /// wheel is a decision taken in front of a waiting class.
  static const colours = <int>[
    0xFFFF5252, // red
    0xFFFFD740, // amber
    0xFF69F0AE, // green
    0xFF448AFF, // blue
  ];

  int _colour = colours.first;
  int get colour => _colour;

  /// How thick the pencil is, as a fraction of the tile's width.
  static const pencilWidth = 0.005;

  /// How wide the rubber's touch is, in the same fractions.
  ///
  /// Wider than the pencil, because a rubber that has to be placed
  /// exactly on a line is a rubber that misses.
  static const eraserRadius = 0.025;

  List<Offset>? _drawing;

  /// The stroke currently under the finger, or null.
  ///
  /// Drawn locally, straight away, and only sent when it is finished.
  /// The person drawing sees their own hand; everybody else sees the
  /// line land a moment later, while the teacher is still talking about
  /// it.
  List<Offset>? get drawing => _drawing == null ? null : List.of(_drawing!);

  void choose(BoardTool next) {
    if (!canDraw || _tool == next) return;
    _tool = next;
    _drawing = null;
    notifyListeners();
  }

  void useColour(int argb) {
    if (!canDraw || _colour == argb) return;
    _colour = argb;
    // Picking up a colour is picking up the pencil. Nobody chooses red
    // in order to carry on rubbing out.
    _tool = BoardTool.pencil;
    notifyListeners();
  }

  void startAt(Offset point) {
    if (!canDraw) return;
    switch (_tool) {
      case BoardTool.pencil:
        _drawing = [point];
        notifyListeners();
      case BoardTool.eraser:
        _eraseAt(point);
      case BoardTool.off:
        return;
    }
  }

  void extendTo(Offset point) {
    if (!canDraw) return;
    switch (_tool) {
      case BoardTool.pencil:
        if (_drawing == null) return;
        _drawing!.add(point);
        notifyListeners();
      case BoardTool.eraser:
        _eraseAt(point);
      case BoardTool.off:
        return;
    }
  }

  /// Lifts the hand, which is when the stroke travels.
  void finish() {
    final points = _drawing;
    _drawing = null;
    if (points == null || !canDraw) {
      notifyListeners();
      return;
    }
    // A tap is a dot, and a dot is a perfectly good thing to put beside
    // a word. Two points, so it has a length and can be found by a
    // rubber.
    final line = points.length == 1
        ? [points.first, points.first + const Offset(0.0005, 0)]
        : thinned(points);
    final mark = Mark(
      id: newMarkId(_random),
      colour: _colour,
      width: pencilWidth,
      points: line,
    );
    _board = _board.add(mark);
    send(MarkDrawn(mark));
    notifyListeners();
  }

  void clear() {
    if (!canDraw || _board.isEmpty) return;
    _board = _board.cleared;
    send(const BoardCleared());
    notifyListeners();
  }

  /// Applies something that arrived from somebody else.
  ///
  /// Anything unreadable is dropped. This runs in the middle of a
  /// lesson, on whatever the network handed over, and a version of the
  /// app that sends a message this one has never heard of must be
  /// ignored rather than allowed to end the class.
  void receive(String text) {
    final message = decodeBoardMessage(text);
    if (message == null) return;
    _board = applyBoardMessage(_board, message);
    notifyListeners();
  }

  /// Sends the whole board to somebody who has just arrived.
  ///
  /// A pupil who joins ten minutes in would otherwise see a clean slide
  /// with the teacher talking about a circle that is not there.
  void resend() {
    if (!canDraw || _board.isEmpty) return;
    send(BoardReplaced(_board));
  }

  void _eraseAt(Offset point) {
    final hit = _board.hits(point, eraserRadius);
    if (hit.isEmpty) return;
    _board = _board.remove(hit);
    // By id, not by the shape of the rubber: "remove these three" lands
    // identically on every device, and "rub here, this hard" does not.
    send(MarksErased(hit));
    notifyListeners();
  }
}
