/// Where the school's video classes are held.
///
/// ## Why not meet.jit.si
///
/// It was the default, because it is free and needs nothing set up. It
/// does not work for this, and the three complaints it produced are one
/// cause:
///
///   * a sign-in page,
///   * "waiting for a moderator",
///   * and the lesson opening in a browser tab instead of in the app.
///
/// The public instance requires the person who creates a room to
/// authenticate, and it no longer welcomes being embedded by other
/// sites -- 8x8 sell that as a product now. So the iframe fails, the
/// screen falls back to handing the room to the browser, and what the
/// person meets there is the sign-in. "Inside the app" was never going
/// to be true on that deployment.
///
/// ## The default now
///
/// A public Jitsi that asks nobody to sign in and is an ordinary Jitsi
/// install, so it embeds. A class opens the lesson and is simply in it.
///
/// **This has not been reached from this environment.** The network
/// policy here denies it, exactly as it denied meet.jit.si, so the first
/// real check is a person on the deployed site. If it is down, or if it
/// stops allowing this, the fix is one Actions variable and not a code
/// change -- see below.
///
/// ## And why a school should still move off it
///
/// It is run by volunteers, for free, with no promise to anybody. A
/// school putting its children's lessons through it is trusting a
/// stranger's server with minors on camera, and has no contract, no
/// support and no say if it goes away on a Monday morning. That is a
/// reasonable way to start and a poor way to run a term.
///
/// Moving is one variable: `JITSI_DOMAIN`, an Actions variable passed
/// to the build, pointed at the school's own deployment or a paid
/// tenant. Set the matching one on the Functions side and LogicClass
/// mints the tokens, so nobody signs in there either. See
/// docs/41-online-classes.md.
const meetingDomain = String.fromEnvironment(
  'JITSI_DOMAIN',
  defaultValue: 'meet.ffmuc.net',
);

/// What a client can do about joining a video class.
enum MeetingSupport {
  /// The meeting renders inside a LogicClass screen. Web, through an
  /// iframe Jitsi drives itself.
  embedded,

  /// The meeting runs in the app, full-screen, through the native Jitsi
  /// SDK. Android and iOS. Not a Flutter widget -- the SDK puts its own
  /// conference in front of the person -- but it is this app's process,
  /// there is no browser, and Leave comes back to the screen behind.
  nativeSdk,

  /// The app hands the room to the operating system -- the Jitsi app if
  /// it is installed, the browser otherwise. Desktop, and the fallback
  /// anywhere the other two fail. Honest, and not the same thing: the
  /// person leaves LogicClass to attend the lesson.
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

  /// Runs the meeting inside the app on a platform with a native SDK.
  ///
  /// Returns false where there is none, or where it would not start --
  /// the screen then falls back to [handOff] rather than leaving
  /// somebody looking at a button that does nothing.
  Future<bool> joinInApp({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
  }) async =>
      false;
}
