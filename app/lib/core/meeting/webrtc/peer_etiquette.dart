/// The rules two browsers follow so they do not talk over each other.
///
/// WebRTC's hard part is not the media, it is that both sides may decide
/// to renegotiate at the same instant -- a camera switched on here while
/// one is switched on there -- and a connection that handles that badly
/// wedges permanently. "Perfect negotiation" is the pattern that fixes
/// it, and all of it is decisions rather than I/O, so all of it is here
/// and under test. The parts that touch a browser hold no rules at all.
library;

/// Which side gives way when both offer at once.
///
/// Exactly one of any pair must be polite, and both must agree on which.
/// Comparing the two peer ids gives that for free: it needs no
/// negotiation of its own, no central authority, and it cannot disagree
/// with itself. Ids are unique per join, so the comparison never ties.
///
/// The polite peer rolls back its own offer and accepts the other's. The
/// impolite one ignores the incoming offer and carries on. If both were
/// polite they would both give way and neither would connect; if neither
/// were, both would hold their own offer and neither would connect.
bool isPolitePeer({required String localId, required String remoteId}) =>
    localId.compareTo(remoteId) > 0;

/// Whether an incoming offer arriving mid-negotiation must be ignored.
///
/// A collision is an offer landing while this side is not in a settled
/// state. The impolite peer ignores it and expects the other to give
/// way; the polite peer accepts it, which means undoing its own offer
/// first.
bool shouldIgnoreOffer({
  required bool polite,
  required bool makingOffer,
  required bool stable,
}) {
  final collision = makingOffer || !stable;
  return collision && !polite;
}

/// Whether a candidate can be applied yet.
///
/// ICE candidates routinely arrive before the description they belong
/// to -- they are sent as they are discovered, and the offer they answer
/// may still be in flight. Applying one early throws, and a thrown
/// candidate is a connection that never completes for reasons nothing
/// logs. They are held until there is a remote description to attach
/// them to.
bool canApplyCandidate({required bool hasRemoteDescription}) =>
    hasRemoteDescription;

/// How many people a call carries, and why it depends on the shape.
///
/// Two topologies, and the difference is not a tuning value:
///
///   * **Mesh** -- every participant sends their own video to every
///     other one. Six people is five uploads each and thirty streams
///     across the room, which an ordinary connection manages. Sixty is
///     fifty-nine uploads from a single laptop and three and a half
///     thousand streams. It does not degrade at that size, it fails.
///   * **Through a media server (an SFU)** -- everybody sends once, to
///     the server, which forwards. One upload each however many are in
///     the room, so a class of sixty costs a participant no more than a
///     call of six.
///
/// A school that teaches classes of sixty therefore needs the second,
/// and no amount of client code substitutes for it. What the client can
/// do is use it when it is there, fall back to mesh when it is not, and
/// never pretend a mesh will hold a class.
enum MeetingTransport {
  /// Direct between browsers. No server, nothing to configure, and a
  /// hard ceiling.
  mesh,

  /// Through a media server that forwards streams.
  forwarded,
}

/// The most a [transport] carries.
///
/// The forwarded number is a policy rather than a limit of the
/// technology -- an SFU will carry far more -- and is set where a
/// Philippine secondary class sits, with room above it. The mesh number
/// is the limit of the technology.
int capacityOf(MeetingTransport transport) => switch (transport) {
      MeetingTransport.mesh => 6,
      MeetingTransport.forwarded => 100,
    };

/// Whether one more person can be let in.
bool hasRoomFor(int currentParticipants, MeetingTransport transport) =>
    currentParticipants < capacityOf(transport);

/// What to say when it does not.
///
/// Names the limit and who fixes it, because "the class is full" in
/// front of a child who was told to join is worse than useless. On a
/// mesh it also says the thing that actually changes the answer, since
/// a school hitting this every morning needs to hear it.
String fullMessage(String subject, MeetingTransport transport) {
  final limit = capacityOf(transport);
  return switch (transport) {
    MeetingTransport.mesh => '$subject already has $limit people in it, which '
        'is as many as a direct call carries. Tell your teacher -- a class '
        'this size needs the school to set up a media server.',
    MeetingTransport.forwarded => '$subject already has $limit people in it. '
        'Tell your teacher.',
  };
}
