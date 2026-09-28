import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/hands.dart';

/// Putting a hand up, and the other things a pupil says without talking.
///
/// The field these travel in is the one thing in the lesson a pupil can
/// write, so most of this is about what happens when they write
/// something else into it.
void main() {
  final now = DateTime(2026, 9, 28, 9, 30);

  group('reading what somebody is signalling', () {
    test('finds a hand and the moment it went up', () {
      final raised = now.subtract(const Duration(minutes: 2));

      final signal = readSignal({
        handKey: '${raised.millisecondsSinceEpoch}',
      });

      expect(signal.handIsUp, isTrue);
      expect(signal.handRaisedAt!.millisecondsSinceEpoch,
          raised.millisecondsSinceEpoch);
    });

    test('survives the journey there and back', () {
      final signal = Signal(
        handRaisedAt: now,
        reaction: Reaction.slower,
        reactedAt: now,
      );

      final back = readSignal(signalAttributes(signal));

      expect(back.handRaisedAt!.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch);
      expect(back.reaction, Reaction.slower);
    });

    test('takes an empty string as nothing, so a hand can come down', () {
      // Attributes are merged, so a missing key leaves the old value in
      // place. An empty one is how a hand goes down at all.
      final down = signalAttributes(const Signal());

      expect(down[handKey], '');
      expect(readSignal(down).handIsUp, isFalse);
    });

    test('ignores anything that is not one of the few things it knows', () {
      // The one field a pupil can write. It is read the way a form is
      // read, not the way a message is: a value that is not expected
      // does not render, and cannot.
      for (final rubbish in [
        'up',
        'true',
        '-1',
        '0',
        'javascript:alert(1)',
        '<script>',
        '99999999999999999999',
      ]) {
        expect(readSignal({handKey: rubbish}).handIsUp, isFalse,
            reason: rubbish);
      }
    });

    test('ignores a reaction nobody has ever heard of', () {
      expect(readSignal({reactionKey: 'shouting'}).reaction, isNull);
      expect(readSignal({reactionKey: 'YES'}).reaction, isNull,
          reason: 'not a near miss either');
      expect(readSignal({reactionKey: 'yes'}).reaction, Reaction.yes);
    });

    test('refuses a hand dated last week or next year', () {
      // A hand at the front of the queue for ever, put there by a clock
      // that is wrong or a number somebody made up.
      final ancient = now.subtract(const Duration(days: 30));
      final future = now.add(const Duration(days: 30));

      expect(readSignal({handKey: '${ancient.millisecondsSinceEpoch}'}).handIsUp,
          isFalse);
      expect(readSignal({handKey: '${future.millisecondsSinceEpoch}'}).handIsUp,
          isFalse);
    });

    test('leaves alone whatever else is in there', () {
      // Other things may use participant attributes one day. This reads
      // its own keys and nothing else.
      final signal = readSignal({
        'something_else': 'not ours',
        handKey: '${now.millisecondsSinceEpoch}',
      });

      expect(signal.handIsUp, isTrue);
    });

    test('has no reaction time without a reaction', () {
      final signal = readSignal({reactedAtKey: '${now.millisecondsSinceEpoch}'});

      expect(signal.reaction, isNull);
      expect(signal.reactedAt, isNull);
    });
  });

  group('a reaction', () {
    test('answers the question being asked, and then stops', () {
      // A "yes" still showing four questions later is worse than no
      // answer at all.
      final just = Signal(reaction: Reaction.yes, reactedAt: now);
      final old = Signal(
        reaction: Reaction.yes,
        reactedAt: now.subtract(reactionLasts + const Duration(seconds: 1)),
      );

      expect(reactionIsFresh(just, now), isTrue);
      expect(reactionIsFresh(old, now), isFalse);
    });

    test('survives a device whose clock runs a little ahead', () {
      // A reaction from the future is two clocks disagreeing, not a
      // reaction to be thrown away.
      final ahead = Signal(
        reaction: Reaction.no,
        reactedAt: now.add(const Duration(seconds: 3)),
      );

      expect(reactionIsFresh(ahead, now), isTrue);
    });

    test('is nothing when there is nothing to show', () {
      expect(reactionIsFresh(Signal.none, now), isFalse);
      expect(reactionIsFresh(Signal(reactedAt: now), now), isFalse);
      expect(reactionIsFresh(const Signal(reaction: Reaction.yes), now), isFalse);
    });

    test('offers four answers and no more', () {
      // A longer list is a menu somebody reads instead of answering,
      // and an emoji keyboard is a lesson about emoji.
      expect(Reaction.values.length, 4);
      for (final reaction in Reaction.values) {
        expect(reaction.label, isNotEmpty);
        expect(reaction.glyph, isNotEmpty);
      }
    });
  });

  group('the teacher\'s list of hands', () {
    Map<String, ({String name, Signal signal})> room(
      List<(String, String, int?)> people,
    ) =>
        {
          for (final (id, name, minutesAgo) in people)
            id: (
              name: name,
              signal: Signal(
                handRaisedAt: minutesAgo == null
                    ? null
                    : now.subtract(Duration(minutes: minutesAgo)),
              ),
            ),
        };

    test('is in the order the hands went up', () {
      // "Whoever the grid happens to draw first" is not an order, it is
      // a lottery a quiet child always loses.
      final hands = handsInOrder(room([
        ('c', 'Cara', 1),
        ('a', 'Ana', 5),
        ('b', 'Ben', 3),
      ]));

      expect([for (final h in hands) h.name], ['Ana', 'Ben', 'Cara']);
    });

    test('leaves out everybody whose hand is down', () {
      final hands = handsInOrder(room([
        ('a', 'Ana', 5),
        ('b', 'Ben', null),
      ]));

      expect([for (final h in hands) h.name], ['Ana']);
    });

    test('does not reshuffle when two hands go up together', () {
      // Under a teacher's finger, as they reach for the first name.
      final together = room([('b', 'Ben', 2), ('a', 'Ana', 2)]);

      expect([for (final h in handsInOrder(together)) h.identity], ['a', 'b']);
      expect([for (final h in handsInOrder(together)) h.identity], ['a', 'b']);
    });

    test('is empty for a class with nothing to say', () {
      expect(handsInOrder(const {}), isEmpty);
      expect(handsInOrder(room([('a', 'Ana', null)])), isEmpty);
    });
  });

  group('how long a hand has been up', () {
    test('is a minute at a time, not a stopwatch', () {
      // "0:47" invites a teacher to watch a clock; "3 min" invites them
      // to call on the child.
      expect(waitingFor(const Duration(seconds: 5)), 'just now');
      expect(waitingFor(const Duration(seconds: 59)), 'just now');
      expect(waitingFor(const Duration(minutes: 1)), '1 min');
      expect(waitingFor(const Duration(minutes: 3, seconds: 40)), '3 min');
    });
  });

  group('the class the teacher reads', () {
    Attendee person(String id, String name, {int? handMinutesAgo}) => Attendee(
          identity: id,
          name: name,
          isMe: false,
          joinedAt: now,
          signal: Signal(
            handRaisedAt: handMinutesAgo == null
                ? null
                : now.subtract(Duration(minutes: handMinutesAgo)),
          ),
        );

    test('puts hands first, in the order they went up', () {
      final order = attendeesInOrder([
        person('d', 'Dina'),
        person('c', 'Cara', handMinutesAgo: 1),
        person('a', 'Ana'),
        person('b', 'Ben', handMinutesAgo: 4),
      ]);

      expect([for (final a in order) a.name], ['Ben', 'Cara', 'Ana', 'Dina']);
    });

    test('and everybody else by name, not by when they joined', () {
      // A register read in join order is a register nobody can find a
      // name in.
      final order = attendeesInOrder([
        person('z', 'Zenaida'),
        person('a', 'ana'),
        person('m', 'Mario'),
      ]);

      expect([for (final a in order) a.name], ['ana', 'Mario', 'Zenaida']);
    });

    test('does not reshuffle under the teacher\'s finger', () {
      final together = [
        person('b', 'Ben', handMinutesAgo: 2),
        person('a', 'Ana', handMinutesAgo: 2),
      ];

      expect([for (final a in attendeesInOrder(together)) a.identity],
          ['a', 'b']);
      expect([for (final a in attendeesInOrder(together)) a.identity],
          ['a', 'b']);
    });

    test('is empty for an empty lesson', () {
      expect(attendeesInOrder(const []), isEmpty);
    });
  });
}
