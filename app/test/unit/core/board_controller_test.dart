import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/board_controller.dart';
import 'package:logicclass/core/meeting/whiteboard.dart';

/// The pencil and the rubber, driven from both ends.
///
/// The seam exists so a test can be the network: what the teacher's
/// device draws goes in one end and comes out of a pupil's. That is the
/// only property of this worth having, and no amount of looking at a
/// screen establishes it.
void main() {
  late List<BoardMessage> wire;
  late LessonBoard teacher;
  late LessonBoard pupil;

  setUp(() {
    wire = [];
    teacher = LessonBoard(
      send: wire.add,
      canDraw: true,
      random: Random(11),
    );
    pupil = LessonBoard(send: (_) {}, canDraw: false);
  });

  /// Everything the teacher sent, delivered to the pupil.
  void deliver() {
    for (final message in wire) {
      pupil.receive(encodeBoardMessage(message));
    }
    wire.clear();
  }

  void drawFrom(LessonBoard board, List<Offset> points) {
    board.startAt(points.first);
    for (final point in points.skip(1)) {
      board.extendTo(point);
    }
    board.finish();
  }

  group('the pencil', () {
    test('draws nothing until a tool is picked up', () {
      // A lesson spends almost all of its time with no tool in hand,
      // and a finger on a shared screen must not leave a line.
      drawFrom(teacher, const [Offset(0.2, 0.2), Offset(0.8, 0.8)]);

      expect(teacher.board.isEmpty, isTrue);
      expect(wire, isEmpty);
    });

    test('shows the line under the finger before anybody else has it', () {
      teacher.choose(BoardTool.pencil);
      teacher.startAt(const Offset(0.2, 0.2));
      teacher.extendTo(const Offset(0.5, 0.5));

      // Local, immediate, and not yet on the wire: the hand holding the
      // device is the only one that would notice the difference.
      expect(teacher.drawing, hasLength(2));
      expect(wire, isEmpty);
      expect(teacher.board.isEmpty, isTrue);
    });

    test('sends the stroke once, when the hand lifts', () {
      teacher.choose(BoardTool.pencil);

      drawFrom(teacher, [
        for (var i = 0; i <= 50; i++) Offset(0.1 + i / 100, 0.5),
      ]);

      expect(wire, hasLength(1), reason: 'once, not once per touch');
      expect(wire.single, isA<MarkDrawn>());
      expect(teacher.drawing, isNull);
      expect(teacher.board.marks, hasLength(1));
    });

    test('puts a dot where a finger only tapped', () {
      teacher.choose(BoardTool.pencil);
      teacher.startAt(const Offset(0.4, 0.4));
      teacher.finish();

      // A dot beside a word is a perfectly good mark, and it has to
      // have enough length that a rubber can find it again.
      final mark = (wire.single as MarkDrawn).mark;
      expect(mark.points.length, greaterThanOrEqualTo(2));
      expect(mark.distanceTo(const Offset(0.4, 0.4)), lessThan(0.001));
    });

    test('arrives on a pupil\'s device as the same stroke', () {
      teacher.choose(BoardTool.pencil);
      drawFrom(teacher, const [Offset(0.1, 0.5), Offset(0.9, 0.5)]);
      deliver();

      expect(pupil.board.marks, hasLength(1));
      expect(
        pupil.board.marks.single.distanceTo(const Offset(0.5, 0.5)),
        lessThan(0.001),
      );
      expect(pupil.board.marks.single.colour, teacher.colour);
    });

    test('changes colour and picks itself back up', () {
      // Nobody chooses red in order to carry on rubbing out.
      teacher.choose(BoardTool.eraser);
      teacher.useColour(LessonBoard.colours.last);

      expect(teacher.tool, BoardTool.pencil);
      expect(teacher.colour, LessonBoard.colours.last);
    });
  });

  group('the rubber', () {
    setUp(() {
      teacher.choose(BoardTool.pencil);
      drawFrom(teacher, const [Offset(0.1, 0.2), Offset(0.9, 0.2)]);
      drawFrom(teacher, const [Offset(0.1, 0.8), Offset(0.9, 0.8)]);
      deliver();
    });

    test('takes out the line it is held against, and leaves the other', () {
      teacher.choose(BoardTool.eraser);
      teacher.startAt(const Offset(0.5, 0.21));

      expect(teacher.board.marks, hasLength(1));
      expect(teacher.board.marks.single.points.first.dy, 0.8);
    });

    test('takes it out on every other device too', () {
      teacher.choose(BoardTool.eraser);
      teacher.startAt(const Offset(0.5, 0.21));
      deliver();

      expect(pupil.board.marks, hasLength(1));
      expect(pupil.board.marks.single.points.first.dy, 0.8);
    });

    test('says nothing when it is dragged across empty space', () {
      teacher.choose(BoardTool.eraser);
      teacher.startAt(const Offset(0.5, 0.5));
      teacher.extendTo(const Offset(0.55, 0.5));

      // A rubber moved over nothing must not put sixty packets a second
      // on the wire saying nothing happened.
      expect(wire, isEmpty);
      expect(teacher.board.marks, hasLength(2));
    });

    test('rubs continuously as it is dragged', () {
      teacher.choose(BoardTool.eraser);
      teacher.startAt(const Offset(0.5, 0.5));
      teacher.extendTo(const Offset(0.5, 0.21));
      teacher.extendTo(const Offset(0.5, 0.79));

      expect(teacher.board.isEmpty, isTrue);
      expect(wire, hasLength(2));
    });
  });

  group('clearing', () {
    test('wipes it here and everywhere', () {
      teacher.choose(BoardTool.pencil);
      drawFrom(teacher, const [Offset(0.1, 0.5), Offset(0.9, 0.5)]);
      deliver();

      teacher.clear();
      deliver();

      expect(teacher.board.isEmpty, isTrue);
      expect(pupil.board.isEmpty, isTrue);
    });

    test('says nothing about a board that is already empty', () {
      teacher.clear();

      expect(wire, isEmpty);
    });
  });

  group('a pupil', () {
    test('cannot draw, whatever the screen offers them', () {
      // Sixty pupils with a pencil over a shared screen is not a
      // lesson. Said here a second time in case a future screen forgets
      // to hide the buttons.
      pupil.choose(BoardTool.pencil);
      pupil.startAt(const Offset(0.2, 0.2));
      pupil.extendTo(const Offset(0.8, 0.8));
      pupil.finish();
      pupil.clear();

      expect(pupil.tool, BoardTool.off);
      expect(pupil.board.isEmpty, isTrue);
    });

    test('still sees everything the teacher draws', () {
      teacher.choose(BoardTool.pencil);
      drawFrom(teacher, const [Offset(0.1, 0.5), Offset(0.9, 0.5)]);
      deliver();

      expect(pupil.board.marks, hasLength(1));
    });

    test('arriving late is sent the board as it stands', () {
      teacher.choose(BoardTool.pencil);
      drawFrom(teacher, const [Offset(0.1, 0.2), Offset(0.9, 0.2)]);
      drawFrom(teacher, const [Offset(0.1, 0.8), Offset(0.9, 0.8)]);
      wire.clear();

      final latecomer = LessonBoard(send: (_) {}, canDraw: false);
      teacher.resend();
      for (final message in wire) {
        latecomer.receive(encodeBoardMessage(message));
      }

      // Otherwise they see a clean slide with the teacher talking about
      // a circle that is not there.
      expect(latecomer.board.marks, hasLength(2));
    });

    test('and is sent nothing when there is nothing on it', () {
      teacher.resend();

      expect(wire, isEmpty);
    });
  });

  test('nonsense from the network is ignored, not thrown', () {
    teacher.choose(BoardTool.pencil);
    drawFrom(teacher, const [Offset(0.1, 0.5), Offset(0.9, 0.5)]);
    deliver();

    for (final rubbish in ['', 'not json', '{}', '{"t":"from-the-future"}']) {
      pupil.receive(rubbish);
    }

    expect(pupil.board.marks, hasLength(1), reason: 'and nothing was lost');
  });

  test('the board tells the screen when it has changed, and only then', () {
    var told = 0;
    teacher
      ..addListener(() => told += 1)
      ..choose(BoardTool.pencil);
    expect(told, 1);

    teacher.choose(BoardTool.pencil);
    expect(told, 1, reason: 'picking up the pencil twice is one pencil');

    teacher.startAt(const Offset(0.2, 0.2));
    expect(told, 2);
  });
}
