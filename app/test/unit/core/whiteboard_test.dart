import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/whiteboard.dart';

/// What a teacher draws on the lesson.
///
/// Tested at the arithmetic, because the arithmetic is what nobody can
/// check by eye: a mark drawn on a laptop and watched on a phone has to
/// land on the same word, and a rubber has to find a line it is held
/// against rather than only the points that happen to be recorded.
void main() {
  Mark strokeAcross({String id = 'a', double y = 0.5}) => Mark(
        id: id,
        colour: 0xFFFF0000,
        width: 0.004,
        points: [Offset(0.1, y), Offset(0.9, y)],
      );

  group('a stroke', () {
    test('is found by a rubber held against its middle', () {
      // Two recorded points, a third of a screen apart. Measuring to
      // the nearest recorded point would miss everything between them,
      // which is most of the line.
      final mark = strokeAcross();

      expect(mark.distanceTo(const Offset(0.5, 0.5)), closeTo(0, 0.0001));
      expect(mark.distanceTo(const Offset(0.5, 0.55)), closeTo(0.05, 0.0001));
    });

    test('stops at its ends rather than running on forever', () {
      final mark = strokeAcross();

      // Off the end of the line, not beside it: the distance is to the
      // end point, not to the infinite line through it.
      expect(mark.distanceTo(const Offset(1.4, 0.5)), closeTo(0.5, 0.0001));
    });

    test('survives the journey there and back', () {
      const mark = Mark(
        id: 'x1',
        colour: 0xFF2196F3,
        width: 0.006,
        points: [Offset(0.1234, 0.5678), Offset(0.2, 0.3)],
      );

      final back = Mark.fromJson(mark.toJson())!;

      expect(back.id, mark.id);
      expect(back.colour, mark.colour);
      expect(back.width, closeTo(mark.width, 0.0001));
      expect(back.points.length, 2);
      expect(back.points.first.dx, closeTo(0.1234, 0.0001));
      expect(back.points.first.dy, closeTo(0.5678, 0.0001));
    });

    test('is refused rather than half-read when it arrives damaged', () {
      for (final broken in <Object?>[
        null,
        'not a map',
        {'i': 'a', 'c': 0, 'w': 0.1},
        {'i': 'a', 'c': 0, 'w': 0.1, 'p': []},
        {'i': 'a', 'c': 0, 'w': 0.1, 'p': ['x', 'y']},
        {'c': 0, 'w': 0.1, 'p': [0.1, 0.2]},
      ]) {
        expect(Mark.fromJson(broken), isNull, reason: '$broken');
      }
    });
  });

  group('the board', () {
    test('keeps what is drawn on it, in the order it was drawn', () {
      final board = const Whiteboard()
          .add(strokeAcross(id: 'a'))
          .add(strokeAcross(id: 'b'));

      expect([for (final m in board.marks) m.id], ['a', 'b']);
    });

    test('replaces a stroke that arrives twice rather than stacking it', () {
      // The same message can be delivered twice, and a stroke drawn on
      // top of itself is a stroke drawn twice as thick.
      final board = const Whiteboard()
          .add(strokeAcross(id: 'a'))
          .add(strokeAcross(id: 'a', y: 0.2));

      expect(board.marks.length, 1);
      expect(board.marks.single.points.first.dy, 0.2);
    });

    test('forgets the oldest once it is full', () {
      var board = const Whiteboard();
      for (var i = 0; i < Whiteboard.limit + 20; i++) {
        board = board.add(strokeAcross(id: 'm$i'));
      }

      expect(board.marks.length, Whiteboard.limit);
      expect(board.marks.first.id, 'm20', reason: 'the oldest twenty went');
      expect(board.marks.last.id, 'm${Whiteboard.limit + 19}');
    });

    test('rubs out what the rubber is over, and nothing else', () {
      final board = const Whiteboard()
          .add(strokeAcross(id: 'top', y: 0.2))
          .add(strokeAcross(id: 'middle', y: 0.5))
          .add(strokeAcross(id: 'bottom', y: 0.8));

      final hit = board.hits(const Offset(0.5, 0.51), 0.02);

      expect(hit, ['middle']);
      expect([for (final m in board.remove(hit).marks) m.id],
          ['top', 'bottom']);
    });

    test('takes several at once when the rubber covers several', () {
      final board = const Whiteboard()
          .add(strokeAcross(id: 'a', y: 0.50))
          .add(strokeAcross(id: 'b', y: 0.51));

      expect(board.hits(const Offset(0.5, 0.505), 0.02), ['a', 'b']);
    });

    test('is unchanged by rubbing at nothing', () {
      final board = const Whiteboard().add(strokeAcross());

      expect(board.remove(const []).marks.length, 1);
      expect(board.remove(const ['nobody']).marks.length, 1);
    });

    test('clears', () {
      expect(const Whiteboard().add(strokeAcross()).cleared.isEmpty, isTrue);
    });
  });

  group('on the wire', () {
    test('a stroke, an erasure, a clearing and a whole board all survive', () {
      final drawn = MarkDrawn(strokeAcross(id: 'z'));
      expect(
        (decodeBoardMessage(encodeBoardMessage(drawn))! as MarkDrawn).mark.id,
        'z',
      );

      const erased = MarksErased(['a', 'b']);
      expect(
        (decodeBoardMessage(encodeBoardMessage(erased))! as MarksErased).ids,
        ['a', 'b'],
      );

      expect(decodeBoardMessage(encodeBoardMessage(const BoardCleared())),
          isA<BoardCleared>());

      final whole = BoardReplaced(
        const Whiteboard().add(strokeAcross(id: 'p')).add(strokeAcross(id: 'q')),
      );
      final back = decodeBoardMessage(encodeBoardMessage(whole))! as BoardReplaced;
      expect([for (final m in back.board.marks) m.id], ['p', 'q']);
    });

    test('anything it cannot read is ignored, never thrown', () {
      // This arrives from the network in the middle of a lesson. A
      // version of the app that sends something this one has never
      // heard of must be ignored, not allowed to end the class.
      for (final rubbish in [
        '',
        'not json',
        '[]',
        '{}',
        '{"t":"something-new"}',
        '{"t":"m"}',
        '{"t":"e"}',
        '{"t":"f","f":"not a list"}',
      ]) {
        expect(decodeBoardMessage(rubbish), isNull, reason: rubbish);
      }
    });

    test('a stroke crosses the network without swelling past what it carries',
        () {
      // LiveKit will not carry a message past about fifteen kilobytes.
      // A long stroke is the one that could reach it.
      final points = [
        for (var i = 0; i < 2000; i++) Offset(i / 2000, 0.5 + i / 8000),
      ];
      final mark = Mark(
        id: 'long',
        colour: 0xFFFFFFFF,
        width: 0.004,
        points: thinned(points),
      );

      expect(encodeBoardMessage(MarkDrawn(mark)).length, lessThan(15000));
    });

    test('applying a message gives the same board on every device', () {
      // The board is rebuilt from messages, so two devices that saw the
      // same messages must hold the same board -- including the one
      // that drew the strokes in the first place.
      var here = const Whiteboard();
      var there = const Whiteboard();
      final messages = <BoardMessage>[
        MarkDrawn(strokeAcross(id: 'a', y: 0.2)),
        MarkDrawn(strokeAcross(id: 'b', y: 0.5)),
        const MarksErased(['a']),
        MarkDrawn(strokeAcross(id: 'c', y: 0.8)),
      ];

      for (final message in messages) {
        here = applyBoardMessage(here, message);
        there = applyBoardMessage(
          there,
          decodeBoardMessage(encodeBoardMessage(message))!,
        );
      }

      expect([for (final m in here.marks) m.id], ['b', 'c']);
      expect([for (final m in there.marks) m.id], ['b', 'c']);
    });
  });

  group('thinning', () {
    test('drops points too close together to be seen', () {
      final crawling = [for (var i = 0; i < 500; i++) Offset(i / 100000, 0.5)];

      expect(thinned(crawling).length, lessThan(10));
    });

    test('keeps where the hand started and where it stopped', () {
      final points = [for (var i = 0; i < 500; i++) Offset(i / 100000, 0.5)];

      final kept = thinned(points);

      expect(kept.first, points.first);
      expect(kept.last, points.last);
    });

    test('leaves a short stroke alone', () {
      const tap = [Offset(0.5, 0.5), Offset(0.51, 0.5)];

      expect(thinned(tap), tap);
    });
  });

  test('two devices do not invent the same stroke id', () {
    final random = Random(7);
    final ids = {for (var i = 0; i < 2000; i++) newMarkId(random)};

    expect(ids.length, 2000);
    expect(ids.every((id) => id.length == 10), isTrue);
  });
}
