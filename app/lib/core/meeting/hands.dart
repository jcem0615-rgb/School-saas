/// Putting a hand up, and the other things a pupil says without talking.
///
/// ## Why this is not a chat
///
/// Sixty microphones in one lesson is not a lesson, so a class that
/// cannot interrupt has to be able to signal. A hand, and four answers
/// to the question a teacher has just asked.
///
/// It travels as **participant attributes** rather than as messages.
/// The difference matters and is the whole reason the token stayed shut:
/// an attribute is one small labelled value a person sets *on
/// themselves*, replacing whatever was there before. It is not a stream
/// anybody can write into, it cannot be addressed to one child, it
/// cannot accumulate, and everything it holds is visible to the teacher
/// and attributable to the person who set it. `canPublishData` -- an
/// actual channel between children -- stays with the teacher alone.
///
/// Anything that is not one of the few values below is ignored on the
/// way in. A pupil who worked out how to put words in the field would
/// find that nothing renders them.
///
/// ## Why the reaction expires and the hand does not
///
/// A reaction answers the question being asked now: it is on the screen
/// for a few seconds and then it is gone, because a "yes" still showing
/// four questions later is worse than no answer. A hand stays up until
/// it is taken down -- by the pupil, by the teacher, or by the lesson
/// ending -- because a hand is a request that has not been dealt with.
library;

/// The four things a class can say at once without anybody unmuting.
///
/// Four, and these four. A teacher asks "is that clear?" and needs to
/// see the room; a longer list is a menu somebody reads instead of
/// answering, and an emoji keyboard is a lesson about emoji.
enum Reaction {
  yes('Yes', '\u{1F44D}'),
  no('No', '\u{1F44E}'),
  slower('Slower', '\u{1F40C}'),
  lost('Lost', '\u{1F615}');

  final String label;
  final String glyph;
  const Reaction(this.label, this.glyph);
}

/// What one person is signalling, right now.
class Signal {
  /// When the hand went up, or null when it is down.
  ///
  /// The time rather than a flag, because a teacher taking hands in
  /// order needs to know who was first -- and "whoever the grid happens
  /// to draw first" is not an order, it is a lottery a quiet child
  /// always loses.
  final DateTime? handRaisedAt;

  /// The last reaction, and when. Shown only while it is fresh.
  final Reaction? reaction;
  final DateTime? reactedAt;

  const Signal({this.handRaisedAt, this.reaction, this.reactedAt});

  static const none = Signal();

  bool get handIsUp => handRaisedAt != null;

  Signal withHand(DateTime? at) =>
      Signal(handRaisedAt: at, reaction: reaction, reactedAt: reactedAt);

  Signal withReaction(Reaction? what, DateTime? at) =>
      Signal(handRaisedAt: handRaisedAt, reaction: what, reactedAt: at);
}

/// How long a reaction stays on the screen.
const reactionLasts = Duration(seconds: 6);

/// Whether a reaction is still answering the question that was asked.
bool reactionIsFresh(Signal signal, DateTime now) {
  final at = signal.reactedAt;
  if (signal.reaction == null || at == null) return false;
  final age = now.difference(at);
  // Negative when the other device's clock runs ahead of this one. A
  // reaction from the future is a clock disagreeing, not a reaction to
  // be thrown away -- so it counts as fresh rather than as expired.
  return age < reactionLasts;
}

/// The keys this app writes. Everything else in there is somebody
/// else's and is left alone.
const handKey = 'lc_hand';
const reactionKey = 'lc_react';
const reactedAtKey = 'lc_react_at';

/// What to put on the wire for a signal.
///
/// An empty string rather than a missing key for "nothing": attributes
/// are merged, so leaving the key out would leave the old value in
/// place and a hand would never come down.
Map<String, String> signalAttributes(Signal signal) => {
      handKey: signal.handRaisedAt?.millisecondsSinceEpoch.toString() ?? '',
      reactionKey: signal.reaction?.name ?? '',
      reactedAtKey: signal.reactedAt?.millisecondsSinceEpoch.toString() ?? '',
    };

/// Reads somebody's signal off their attributes.
///
/// Everything unrecognised becomes nothing. This is the one field in
/// the lesson a pupil can write, so it is read the way a form is read
/// rather than the way a message is: a value that is not one of the few
/// expected ones does not render, and cannot.
Signal readSignal(Map<String, String> attributes) {
  DateTime? at(String key) {
    final raw = attributes[key];
    if (raw == null || raw.isEmpty) return null;
    final millis = int.tryParse(raw);
    if (millis == null || millis <= 0) return null;
    // A time far outside anything a lesson could hold is a clock that
    // is wrong or a value somebody made up. Either way it must not put
    // a hand at the front of the queue for ever.
    final when = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (when.isBefore(now.subtract(const Duration(days: 1)))) return null;
    if (when.isAfter(now.add(const Duration(days: 1)))) return null;
    return when;
  }

  final named = attributes[reactionKey];
  final reaction = named == null || named.isEmpty
      ? null
      : Reaction.values.where((r) => r.name == named).firstOrNull;

  return Signal(
    handRaisedAt: at(handKey),
    reaction: reaction,
    reactedAt: reaction == null ? null : at(reactedAtKey),
  );
}

/// One person with their hand up.
class RaisedHand {
  final String identity;
  final String name;
  final DateTime since;

  const RaisedHand({
    required this.identity,
    required this.name,
    required this.since,
  });
}

/// Who has a hand up, in the order they put it up.
///
/// Oldest first, and ties broken by identity so the list does not
/// reshuffle itself under a teacher's finger when two hands go up in
/// the same millisecond.
List<RaisedHand> handsInOrder(Map<String, ({String name, Signal signal})> room) {
  final raised = <RaisedHand>[
    for (final entry in room.entries)
      if (entry.value.signal.handRaisedAt case final since?)
        RaisedHand(
          identity: entry.key,
          name: entry.value.name,
          since: since,
        ),
  ];
  raised.sort((a, b) {
    final byTime = a.since.compareTo(b.since);
    return byTime != 0 ? byTime : a.identity.compareTo(b.identity);
  });
  return raised;
}

/// How long a hand has been up, for the teacher's list.
///
/// Minutes once it has been a minute, because "0:47" invites a teacher
/// to watch a stopwatch and "3 min" invites them to call on the child.
String waitingFor(Duration waited) {
  if (waited.inMinutes < 1) return 'just now';
  if (waited.inMinutes == 1) return '1 min';
  return '${waited.inMinutes} min';
}

/// The teacher asking for hands to come down.
///
/// A pupil cannot be made to change their own attribute by anybody
/// else, so this travels the other way: the teacher sends it on the
/// channel only a teacher can send on, and each device lowers its own
/// hand when it sees its name -- or the star that means everybody.
const lowerHandsTopic = 'hands';
const everybody = '*';

/// One person in the lesson, as the teacher's panel sees them.
///
/// This is what "the teacher can see who joined and what they are
/// doing" actually means: a row per person, live, with the things a
/// teacher would otherwise have to squint at sixty tiles to work out.
class Attendee {
  final String identity;
  final String name;

  /// This device's own participant.
  final bool isMe;

  /// When they arrived. A child who joined twenty minutes late is a
  /// thing a register should show and a grid of tiles cannot.
  final DateTime joinedAt;

  /// Whether their microphone and camera are actually on.
  final bool speaking;
  final bool micOn;
  final bool cameraOn;

  /// Putting a window in front of the class.
  final bool sharingScreen;

  /// Hand, and reaction.
  final Signal signal;

  const Attendee({
    required this.identity,
    required this.name,
    required this.isMe,
    required this.joinedAt,
    this.speaking = false,
    this.micOn = false,
    this.cameraOn = false,
    this.sharingScreen = false,
    this.signal = Signal.none,
  });
}

/// The class, in the order a teacher wants to read it.
///
/// Hands first and in the order they went up, because that list is the
/// one being acted on; then everybody else by name, because a register
/// read in join order is a register nobody can find a name in.
List<Attendee> attendeesInOrder(List<Attendee> all) {
  final raised = [for (final a in all) if (a.signal.handIsUp) a]
    ..sort((a, b) {
      final byTime = a.signal.handRaisedAt!.compareTo(b.signal.handRaisedAt!);
      return byTime != 0 ? byTime : a.identity.compareTo(b.identity);
    });
  final rest = [for (final a in all) if (!a.signal.handIsUp) a]
    ..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.identity.compareTo(b.identity);
    });
  return [...raised, ...rest];
}
