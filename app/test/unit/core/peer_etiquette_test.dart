import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/webrtc/peer_etiquette.dart';

/// The rules two browsers follow so they do not talk over each other.
///
/// Pinned hard, because every one of these failures looks the same from
/// the outside -- a call that never connects, with nothing in any log --
/// and that is the failure mode this module has spent a week in already.
void main() {
  group('politeness', () {
    test('exactly one of a pair gives way', () {
      // Both polite and neither would connect: one gives way and the
      // other gives way, so nobody holds an offer. Neither polite and
      // both hold their own. It has to be exactly one.
      const a = 'peer_aaa';
      const b = 'peer_bbb';
      final one = isPolitePeer(localId: a, remoteId: b);
      final other = isPolitePeer(localId: b, remoteId: a);
      expect(one, isNot(other));
    });

    test('both sides agree without asking each other', () {
      // The whole point of deriving it from the ids: there is no
      // handshake to get wrong, and no authority to be unavailable.
      for (final pair in const [
        ['peer_1', 'peer_2'],
        ['zzz', 'aaa'],
        ['lc-9f3', 'lc-0a1'],
      ]) {
        expect(
          isPolitePeer(localId: pair[0], remoteId: pair[1]),
          isNot(isPolitePeer(localId: pair[1], remoteId: pair[0])),
        );
      }
    });
  });

  group('an offer arriving mid-negotiation', () {
    test('is ignored by the impolite side', () {
      expect(
        shouldIgnoreOffer(polite: false, makingOffer: true, stable: false),
        isTrue,
      );
    });

    test('is accepted by the polite side, which will roll back', () {
      expect(
        shouldIgnoreOffer(polite: true, makingOffer: true, stable: false),
        isFalse,
      );
    });

    test('is accepted by either side when there is no collision', () {
      // Nothing in flight: an offer is just an offer.
      expect(
        shouldIgnoreOffer(polite: false, makingOffer: false, stable: true),
        isFalse,
      );
      expect(
        shouldIgnoreOffer(polite: true, makingOffer: false, stable: true),
        isFalse,
      );
    });

    test('an unstable connection is a collision even with no offer out', () {
      // Mid-rollback, mid-answer: not settled is not safe.
      expect(
        shouldIgnoreOffer(polite: false, makingOffer: false, stable: false),
        isTrue,
      );
    });
  });

  group('candidates', () {
    test('wait for a description to attach to', () {
      // They are sent as they are found, and routinely arrive before
      // the offer they belong to. Applying one early throws, and a
      // thrown candidate is a call that never completes with nothing
      // logged anywhere.
      expect(canApplyCandidate(hasRemoteDescription: false), isFalse);
      expect(canApplyCandidate(hasRemoteDescription: true), isTrue);
    });
  });

  group('how many a call carries', () {
    test('a mesh stops at six rather than degrading past it', () {
      // Everybody sends to everybody: six is five uploads each, sixty
      // is fifty-nine. It does not get worse at that size, it stops
      // working -- so it is a limit, not a hint.
      expect(hasRoomFor(0, MeetingTransport.mesh), isTrue);
      expect(hasRoomFor(5, MeetingTransport.mesh), isTrue);
      expect(hasRoomFor(6, MeetingTransport.mesh), isFalse);
      expect(hasRoomFor(60, MeetingTransport.mesh), isFalse);
    });

    test('a forwarded call holds a whole class', () {
      // Through a media server everybody sends once. A class of sixty
      // costs a participant no more than a call of six.
      expect(hasRoomFor(60, MeetingTransport.forwarded), isTrue);
      expect(hasRoomFor(99, MeetingTransport.forwarded), isTrue);
    });

    test('and still has an end, so the failure is ours to word', () {
      expect(hasRoomFor(100, MeetingTransport.forwarded), isFalse);
    });

    test('a full mesh says what actually changes the answer', () {
      final said = fullMessage('Mathematics', MeetingTransport.mesh);
      expect(said, contains('Mathematics'));
      expect(said, contains('6'));
      // A child told to join and met with "full" needs to know it is
      // not their fault and who fixes it.
      expect(said, contains('teacher'));
      expect(said.toLowerCase(), contains('media server'));
    });

    test('a full forwarded call does not blame the topology', () {
      // Nothing the school can configure changes this one, so saying
      // "set up a media server" to somebody who has would be noise.
      final said = fullMessage('Mathematics', MeetingTransport.forwarded);
      expect(said.toLowerCase(), isNot(contains('media server')));
      expect(said, contains('teacher'));
    });
  });
}
