/// Where the school's video classes are held.
///
/// The domain is configurable rather than hardcoded, because which Jitsi
/// a school uses is a decision about their data, not about this app. The
/// default is the public one, which is free and needs nothing set up --
/// good enough to try the feature the afternoon a typhoon closes the
/// school, and not what a school should run a term on. A school that
/// cares where its children's lessons are hosted points this at its own
/// deployment, or at a paid tenant, with one build flag and no code
/// change.
///
/// Verify the public instance before promising it to a school: Jitsi has
/// changed the terms of meet.jit.si more than once, including requiring
/// the first person in to sign in before the room will start. That is
/// survivable for a teacher and fatal for a class of ten-year-olds, and
/// it is exactly the kind of thing that is true or false on the day
/// rather than in documentation.
const meetingDomain = String.fromEnvironment(
  'JITSI_DOMAIN',
  defaultValue: 'meet.jit.si',
);

/// What a client can do about joining a video class.
enum MeetingSupport {
  /// The meeting renders inside the app. Web today.
  embedded,

  /// The app hands the room to the device -- the Jitsi app if it is
  /// installed, the browser otherwise. Honest, and not the same thing:
  /// the person leaves LogicClass to attend the lesson.
  handOff,
}

/// The way into a video class on this platform.
abstract class MeetingLauncher {
  const MeetingLauncher();

  MeetingSupport get support;

  /// The full address of [room] on the configured deployment.
  ///
  /// Built here rather than stored, so the room name is the only thing
  /// that ever travels: a stored URL would pin a school's lessons to
  /// whichever domain was configured on the day the class was opened.
  String urlFor(String room) => 'https://$meetingDomain/$room';

  /// Opens the room for a person who is not inside a screen that can
  /// embed it. Returns false when the device refused.
  Future<bool> handOff(String room, {required String displayName});
}
