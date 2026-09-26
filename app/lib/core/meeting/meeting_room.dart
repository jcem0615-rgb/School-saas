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
  String urlFor(
    String room, {
    String? displayName,
    bool muted = false,
    String? token,
  }) =>
      meetingUrl(room: room, displayName: displayName, muted: muted, token: token);

  /// Opens the room for a person who is not inside a screen that can
  /// embed it. Returns false when the device refused.
  Future<bool> handOff(
    String room, {
    required String displayName,
    String? token,
    bool muted = false,
  });

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

/// The full address of a lesson, for a person arriving outside the app.
///
/// The hand-off is what happens when the video cannot run inside
/// LogicClass -- a deployment that refuses to be embedded, a desktop
/// build, a browser that will not have it. It is the difference between
/// the lesson happening somewhere else and the lesson not happening, so
/// it is worth arriving properly rather than on a stranger's front door.
///
/// Both callers were getting it wrong in different ways. The browser
/// passed the room and nothing else, so a class landed on a prejoin
/// screen asking each child to type their name -- in a lesson whose
/// whole point is a register that matches names to faces. The phone
/// passed the name by pasting it into the fragment unescaped, so
/// "Maria Dela Cruz" became a URL with spaces in it and anything with a
/// quote in it broke the config Jitsi parses.
///
/// So: one builder, escaped, used by both.
///
///   * the name, as a JSON string, so a space or an apostrophe survives
///     and a quote cannot break out of it;
///   * no prejoin page, because they already pressed join;
///   * muted on arrival for everyone but the teacher;
///   * the token, when there is one, as a query parameter -- Jitsi
///     reads `jwt` from the query and not from the fragment.
String meetingUrl({
  required String room,
  String? displayName,
  bool muted = false,
  String? token,
  String domain = meetingDomain,
}) {
  final config = <String>[
    'config.prejoinPageEnabled=false',
    'config.prejoinConfig.enabled=false',
    if (muted) 'config.startWithAudioMuted=true',
    if (muted) 'config.startWithVideoMuted=true',
    if (displayName != null && displayName.isNotEmpty)
      'userInfo.displayName=${Uri.encodeComponent(_jsonString(displayName))}',
  ];
  final query = token == null || token.isEmpty
      ? ''
      : '?jwt=${Uri.encodeQueryComponent(token)}';
  return 'https://$domain/$room$query#${config.join('&')}';
}

/// A name as a JSON string literal.
///
/// Jitsi parses these fragment values as JSON, so the quotes are part
/// of the value and anything quote-like inside has to be escaped rather
/// than passed through. Control characters are dropped: none of them
/// belong in a person's name, and each is a way to end the literal
/// early.
String _jsonString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(RegExp(r'[\x00-\x1f]'), '');
  return '"$escaped"';
}

/// What to conclude when the wait for a joined conference runs out.
///
/// The rule that was got backwards, and the cost of getting it backwards
/// is tearing down a lesson that was about to work.
///
/// Two different failures look the same from outside the iframe: a
/// deployment that refuses to be embedded, where nothing ever happens at
/// all, and a slow join -- a cold room on a distant server from a
/// school's connection -- which is simply taking its time. Treating the
/// second as the first calls `dispose()` on a live conference and the
/// class watches Jitsi say "you have been disconnected", because it has
/// been, by us.
///
/// So the signal is not "did it join in time" but **did anything happen
/// at all**. A frame that has spoken once is a frame that is alive, and
/// a live call is Jitsi's to manage: its own reconnection notice is a
/// better thing to show a class than a screen that kills the lesson at
/// twenty seconds and offers a tab.
///
/// Only silence -- no event of any kind -- means the frame is dead and
/// worth taking down.
bool meetingIsWorthKeeping({required bool anySignal, required bool joined}) =>
    joined || anySignal;
