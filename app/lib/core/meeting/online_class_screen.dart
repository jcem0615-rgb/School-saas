import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'dart:async';

import 'class_clock.dart';
import 'meeting_launcher_factory.dart';
import 'meeting_surface.dart';

/// The lesson, held in the app.
///
/// One screen for both sides of the class: the teacher arrives as the
/// moderator with their camera on, the students muted, because forty
/// microphones opening at once is how an online lesson starts badly.
///
/// What it does depends on what the platform can do, and it says which
/// rather than pretending:
///
///   * **Browser** -- the meeting renders in this screen, in a platform
///     view Jitsi attaches its iframe to.
///   * **Android, iOS** -- the native SDK puts its own full-screen
///     conference in front of the person, in this app's process. Not a
///     Flutter widget, so this screen waits behind it and Leave comes
///     back here.
///   * **Desktop** -- no SDK exists, so the room goes to the operating
///     system and the screen says so.
class OnlineClassScreen extends StatefulWidget {
  final String room;
  final String subject;
  final String section;
  final String displayName;

  /// The teacher, who starts un-muted and can end the call for everyone.
  final bool asModerator;

  /// The signed pass from LogicClass, so the meeting never asks who
  /// this is. Null where the school has configured no signing key, and
  /// the room is joined without one -- which is what happened before
  /// tokens existed and is right on a deployment that does not ask.
  final String? token;

  /// When the teacher pressed Time In, and how long the timetable says
  /// this class is. Both optional: the classroom works without a clock,
  /// it just cannot show one.
  final DateTime? openedAt;
  final int? scheduledMinutes;

  /// Stand-ins for the platform, so the embedded path can be driven from
  /// a test. On every real build these are null and the platform's own
  /// are used; see [MeetingSurface] for why the seam exists.
  @visibleForTesting
  final MeetingSurface? debugSurface;
  @visibleForTesting
  final MeetingLauncher? debugLauncher;

  const OnlineClassScreen({
    super.key,
    required this.room,
    required this.subject,
    required this.section,
    required this.displayName,
    this.token,
    this.asModerator = false,
    this.openedAt,
    this.scheduledMinutes,
    this.debugSurface,
    this.debugLauncher,
  });

  @override
  State<OnlineClassScreen> createState() => _OnlineClassScreenState();
}

class _OnlineClassScreenState extends State<OnlineClassScreen> {
  late final MeetingLauncher _launcher =
      widget.debugLauncher ?? createMeetingLauncher();
  late final MeetingSurface _surface =
      widget.debugSurface ?? const PlatformMeetingSurface();

  /// Null while we are still finding out.
  bool? _ready;
  bool _handedOff = false;

  /// Mirrored rather than read back from Jitsi: the iframe API reports
  /// these through events, and a control that waits for a round trip
  /// before it looks pressed feels broken on a slow connection.
  ///
  /// Notifiers rather than fields, for the same reason as the clock
  /// below: nothing about a button may rebuild the meeting.
  final _muted = ValueNotifier(false);
  final _cameraOff = ValueNotifier(false);

  /// Drives the class clock, and **only** the class clock.
  ///
  /// This was `setState(() {})` on a one-second timer, which rebuilt the
  /// whole screen -- the Stack, and with it the platform view holding
  /// Jitsi's iframe. A browser reloads an iframe that is moved in the
  /// DOM, and Flutter reparents a platform view's host element when the
  /// scene around it changes. So the lesson was being re-scened once a
  /// second, and what the class saw was Jitsi announcing it had been
  /// disconnected, over and over, on a connection that was fine.
  ///
  /// A notifier the controls listen to instead. The meeting is not in
  /// that subtree and never rebuilds for a tick.
  final _now = ValueNotifier(DateTime.now());
  Timer? _tick;

  /// Set once connecting has gone on long enough to be worth doubting.
  ///
  /// The embed is still being attempted -- this only puts the way out on
  /// screen. A deployment that refuses to be framed takes the full
  /// timeout to say so, and a class should not spend it watching a
  /// spinner with nothing to press.
  bool _slow = false;
  Timer? _patience;

  /// Which step of coming up we are on, and how long it has taken.
  ///
  /// On screen, deliberately. Every failure in this module so far has
  /// been diagnosed from a screenshot of a spinner, which is the least
  /// informative thing a screen can show: "loading" is true of fetching
  /// a script, of waiting for a frame that will never exist, and of
  /// joining a room on a slow morning, and those want three different
  /// answers. Naming the step turns a screenshot into a bug report.
  ///
  /// Notifiers, and the counter is driven off one, because rebuilding
  /// this screen on a timer is what was disconnecting the class.
  final _stage = ValueNotifier('Starting');
  final _elapsed = ValueNotifier(0);
  Timer? _counting;

  /// Where it got to, kept for the failure card.
  String _failedAt = '';

  /// The meeting is on screen but has not said a word to us.
  ///
  /// Not a failure and not treated as one. Jitsi's events only start
  /// once the app inside the iframe has finished downloading itself and
  /// opened a channel back to this page -- several megabytes, from a
  /// server that may be a continent away. Silence means "still coming",
  /// and the class can watch it come.
  final _stalled = ValueNotifier(false);

  /// How long before the way out appears. Long enough that a lesson on a
  /// good connection never sees it, short enough that a lesson on a bad
  /// morning is not held hostage to the timeout.
  static const _patienceWindow = Duration(seconds: 4);

  /// The point at which connecting has definitively failed, whatever the
  /// steps below believe.
  ///
  /// Every path through [_start] is bounded, and it still ended up on
  /// screen as an endless spinner -- so this exists because reasoning
  /// about the bounds was not enough. A class must always be able to
  /// leave a loading screen, including through a bug nobody has found
  /// yet. Longer than the sum of the individual waits, so it only fires
  /// when one of them has not.
  static const _giveUpAfter = Duration(seconds: 40);
  Timer? _watchdog;

  bool get _embeds => _launcher.support == MeetingSupport.embedded;
  bool get _native => _launcher.support == MeetingSupport.nativeSdk;

  @override
  void initState() {
    super.initState();
    if (_embeds) {
      _patience = Timer(_patienceWindow, () {
        if (mounted && _ready == null) setState(() => _slow = true);
      });
      _counting = Timer.periodic(const Duration(seconds: 1), (t) {
        // Notifier, not setState. See [_now].
        _elapsed.value = t.tick;
      });
      _watchdog = Timer(_giveUpAfter, () {
        if (!mounted || _ready != null) return;
        _failedAt = 'Gave up ${_stage.value.toLowerCase()} after '
            '${_giveUpAfter.inSeconds} seconds.';
        if (_embeds) _surface.leave(widget.room);
        setState(() => _ready = false);
      });
      _start();
    } else if (_native) {
      _startNative();
    } else {
      _ready = false;
    }
  }

  /// Hands the lesson to the platform SDK, which draws over this screen.
  ///
  /// This screen stays mounted underneath and is what the person comes
  /// back to when they leave the call, so it shows the same fallback --
  /// a way back in if they left by accident.
  Future<void> _startNative() async {
    final joined = await _launcher.joinInApp(
      room: widget.room,
      displayName: widget.displayName,
      subject: '${widget.subject} - ${widget.section}',
      asModerator: widget.asModerator,
    );
    if (!mounted) return;
    // False either way here: the SDK is in front of them if it worked,
    // and if it did not the fallback is what should be behind it.
    setState(() => _ready = false);
    if (!joined) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('The class could not start on this device.'),
        ));
    }
  }

  Future<void> _start() async {
    // Ordered, and the order is the whole fix.
    //
    // This used to load the script, wait one frame and hand Jitsi the
    // element it draws into -- except the element is created by the
    // platform view, and the platform view was only built once this
    // finished. Nothing ever built it, so `getElementById` returned null
    // on every attempt, Jitsi threw on the null parent, the throw
    // escaped this un-awaited future, and the screen showed a spinner
    // until the tab was closed. A class watched it forever.
    //
    // The view is now in the tree behind the spinner from the first
    // frame, so there is a real element to wait for, and every way this
    // can fail ends at the fallback rather than at the spinner.
    try {
      _stage.value = 'Loading the video service';
      final loaded = await _surface.prepare();
      if (!mounted) return;
      if (!loaded) {
        _failedAt = '$meetingDomain did not send its video service.';
        // The script did not come. A lesson is not worth a red screen --
        // the fallback below opens it in a tab.
        setState(() => _ready = false);
        return;
      }

      _stage.value = 'Preparing the meeting frame';
      final host = await _surface.awaitHost(widget.room);
      if (!mounted) return;
      if (!host) {
        _failedAt = 'The app could not make room for the video.';
        setState(() => _ready = false);
        return;
      }

      final started = _surface.start(
        room: widget.room,
        displayName: widget.displayName,
        subject: '${widget.subject} - ${widget.section}',
        asModerator: widget.asModerator,
        token: widget.token,
      );
      if (!started) {
        _failedAt = 'The meeting would not start in this browser.';
        setState(() => _ready = false);
        return;
      }

      // Constructed is not joined. The iframe belongs to another origin
      // and a deployment that refuses to be embedded fails inside it,
      // where nothing here can see -- which is how a blocked frame came
      // to render as a furnished classroom with a dead grey rectangle
      // in the middle of it. Jitsi says when it is in; until it does,
      // this is still connecting.
      // On screen now. The constructor returned with a real parent, so
      // the iframe exists and is loading Jitsi; what happens next is
      // Jitsi's to show, and it shows it better than a spinner does.
      //
      // This used to wait for an event first. Nothing arrived -- the
      // app inside the frame was still downloading -- and the wait
      // ended by disposing a conference that was on its way up. The
      // class was kept from a working lesson by a screen insisting it
      // had not heard anything yet.
      _reveal();

      _stage.value = 'Joining the room';
      final joined = await _surface.awaitJoined(
        widget.room,
        // Stand aside as soon as there is a meeting to look at, rather
        // than holding an overlay over a working call until it finishes
        // joining. A cold room on a distant server takes its time, and
        // Jitsi narrates that better than a spinner does.
        onAlive: _reveal,
      );
      if (!mounted) return;
      if (!mounted) return;
      // Still nothing heard. The frame stays -- it may be a lesson that
      // is simply slow, and tearing it down would end one that was
      // working. What changes is that the class is told, and offered
      // another go, over the top of the meeting rather than instead of
      // it.
      _stalled.value = !joined;
    } catch (error) {
      // Swallowed deliberately, and this is the safety net rather than
      // the fix: the failure above is now handled by value. Anything
      // still thrown here -- third-party script, a browser that will not
      // run it -- must land on the fallback, because the alternative is
      // the bug this commit exists for.
      debugPrint('The online class could not start: $error');
      if (!mounted) return;
      _failedAt = 'Something went wrong while ${_stage.value.toLowerCase()}.';
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _patience?.cancel();
    _counting?.cancel();
    _watchdog?.cancel();
    _stage.dispose();
    _elapsed.dispose();
    _stalled.dispose();
    _now.dispose();
    _muted.dispose();
    _cameraOff.dispose();
    if (_embeds) _surface.leave(widget.room);
    super.dispose();
  }

  /// Hands the screen over to the meeting.
  ///
  /// Idempotent: it is called both on the first sign of life and again
  /// on the join, and the second call must not restart anything.
  void _reveal() {
    if (!mounted || _ready == true) return;
    _watchdog?.cancel();
    _counting?.cancel();
    _startClock();
    setState(() => _ready = true);
  }

  /// Starts the clock, once there is something to time.
  void _startClock() {
    if (_tick != null || widget.openedAt == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      // Deliberately not setState. See [_now].
      if (mounted) _now.value = DateTime.now();
    });
  }

  void _toggleMute() {
    _surface.command(widget.room, 'toggleAudio');
    _muted.value = !_muted.value;
  }

  void _toggleCamera() {
    _surface.command(widget.room, 'toggleVideo');
    _cameraOff.value = !_cameraOff.value;
  }

  void _leave() {
    // Hangs up before popping. Popping alone tears the iframe out of the
    // page with the conference still joined, which leaves somebody in a
    // room nobody can see them in.
    _surface.command(widget.room, 'hangup');
    Navigator.of(context).maybePop();
  }

  Future<void> _rejoinNative() async {
    setState(() => _ready = null);
    await _startNative();
  }

  /// Throws the meeting away and builds it again, in place.
  ///
  /// This used to open a browser tab. It does not any more: the lesson
  /// is meant to happen in this app, and sending a class out to a tab is
  /// the thing the whole module exists to avoid -- it loses the class
  /// clock, the register beside it, and on a phone it loses the app.
  ///
  /// So the way out of a failed attempt is another attempt. The old
  /// frame is disposed first, because retrying on top of a half-built
  /// one is how two connections to the same room appear.
  Future<void> _retry() async {
    if (_embeds) _surface.leave(widget.room);
    if (!mounted) return;
    setState(() {
      _ready = null;
      _slow = false;
    });
    _patience?.cancel();
    _patience = Timer(_patienceWindow, () {
      if (mounted && _ready == null) setState(() => _slow = true);
    });
    _elapsed.value = 0;
    _stalled.value = false;
    _counting?.cancel();
    _counting = Timer.periodic(const Duration(seconds: 1), (t) {
      _elapsed.value = t.tick;
    });
    _watchdog?.cancel();
    _watchdog = Timer(_giveUpAfter, () {
      if (!mounted || _ready != null) return;
      _failedAt = 'Gave up ${_stage.value.toLowerCase()} after '
          '${_giveUpAfter.inSeconds} seconds.';
      if (_embeds) _surface.leave(widget.room);
      setState(() => _ready = false);
    });
    await _start();
  }

  Future<void> _openOutside() async {
    final ok = await _launcher.handOff(
      widget.room,
      displayName: widget.displayName,
      token: widget.token,
      // Everyone but the teacher arrives quiet. Forty microphones
      // opening at once is how an online lesson starts badly, and the
      // tab must not be the way round that.
      muted: !widget.asModerator,
    );
    if (!mounted) return;
    setState(() => _handedOff = ok);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('This device could not open the class.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject),
        // The section, because a teacher takes the same subject four
        // times over and needs to know which one they are in.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(widget.section, style: theme.textTheme.bodySmall),
          ),
        ),
      ),
      // The classroom's own controls sit under the call rather than
      // inside it: Jitsi's toolbar is in the iframe and scales with it,
      // and on a phone-width browser it becomes a row of icons a child
      // has to guess at. These are labelled, and they carry the one
      // thing Jitsi cannot know -- how much of the lesson is left.
      bottomNavigationBar: _ready == true
          ? _ClassroomControls(
              stalled: _stalled,
              onRetry: _retry,
              openedAt: widget.openedAt,
              scheduledMinutes: widget.scheduledMinutes,
              now: _now,
              muted: _muted,
              cameraOff: _cameraOff,
              onMute: _toggleMute,
              onCamera: _toggleCamera,
              onLeave: _leave,
            )
          : null,
      body: _ready == false
          ? _Fallback(
              embedded: _embeds,
              native: _native,
              handedOff: _handedOff,
              reason: _failedAt,
              // Web never leaves the app: another attempt, in place.
              // The hand-off remains only for a desktop build, where
              // there is no embedded view and no SDK, so a tab is the
              // only thing there is rather than a shortcut out of one.
              onOpen: _native
                  ? _rejoinNative
                  : _embeds
                      ? _retry
                      : _openOutside,
            )
          // The view is built while we are still connecting, not after.
          // It is what creates the element the meeting attaches to, so
          // leaving it out until the meeting had started was a circle
          // with no way in. The overlay is opaque, so a half-built
          // iframe is not on show underneath it.
          : Stack(
              fit: StackFit.expand,
              children: [
                // Keyed, so a rebuild matches this to the same element
                // and Flutter has no reason to make a new platform view.
                // A new host element means a new iframe, and a new
                // iframe means the lesson starts again.
                if (_embeds)
                  KeyedSubtree(
                    key: ValueKey('meeting-${widget.room}'),
                    child: _surface.view(widget.room),
                  ),
                if (_ready == null)
                  _Connecting(
                    stage: _stage,
                    elapsed: _elapsed,
                    onRetry: _slow ? _retry : null,
                  ),
              ],
            ),
    );
  }
}

/// What is on screen while the meeting is being brought up.
///
/// Opaque, because the platform view is live behind it from the first
/// frame now. It says what it is waiting for: a bare spinner over a
/// school's video class is indistinguishable from a broken one, which is
/// exactly how this screen's failure was read.
class _Connecting extends StatelessWidget {
  /// Offered once this has gone on long enough to doubt. Null while it
  /// is still within the time a lesson normally takes to come up --
  /// a retry offered immediately reads as an expectation of failure.
  final VoidCallback? onRetry;

  /// The step being waited on, and for how long.
  final ValueListenable<String> stage;
  final ValueListenable<int> elapsed;

  const _Connecting({
    required this.stage,
    required this.elapsed,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Connecting to the class', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Joining $meetingDomain. This takes a few seconds.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            // The step, and the seconds. A spinner says "loading", which
            // is equally true of a script that will never arrive, a
            // frame that cannot exist and a room that is simply slow --
            // three problems with three different answers. This says
            // which.
            ValueListenableBuilder<String>(
              valueListenable: stage,
              builder: (context, step, _) => ValueListenableBuilder<int>(
                valueListenable: elapsed,
                builder: (context, seconds, _) => Text(
                  '$step... ${seconds}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              Text(
                'Taking longer than it should.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try joining again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The lesson's own controls, and its clock.
///
/// Takes notifiers rather than values, so a tick of the clock or a press
/// of Mute rebuilds this bar and nothing else. The meeting must not be
/// in any subtree that a second hand can rebuild -- see [_now] on the
/// screen for what that cost.
class _ClassroomControls extends StatelessWidget {
  /// The meeting is up but has never spoken to us. Says so, over the
  /// meeting rather than instead of it: a lesson that is merely slow
  /// must not be ended by a screen that has not heard from it.
  final ValueListenable<bool> stalled;
  final VoidCallback onRetry;
  final DateTime? openedAt;
  final int? scheduledMinutes;
  final ValueListenable<DateTime> now;
  final ValueListenable<bool> muted;
  final ValueListenable<bool> cameraOff;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onLeave;

  const _ClassroomControls({
    required this.stalled,
    required this.onRetry,
    required this.openedAt,
    required this.scheduledMinutes,
    required this.now,
    required this.muted,
    required this.cameraOff,
    required this.onMute,
    required this.onCamera,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = openedAt;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: stalled,
              builder: (context, quiet, _) => quiet
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              // Says the likely answer rather than
                              // "still connecting" forever. Twenty
                              // seconds of total silence, with the
                              // browser showing a broken frame, is a
                              // server refusing to be embedded far more
                              // often than it is a slow morning -- and
                              // a teacher staring at a grey box
                              // deserves to be told which, and what
                              // actually fixes it.
                              // Written for the teacher in front of a
                              // class, not for whoever will fix it. The
                              // first version named a markdown file in
                              // a git repository, which is a developer
                              // artifact and useless to the person
                              // reading it at half past eight with
                              // thirty children waiting.
                              '$meetingDomain has not started the class inside '
                              'the app. If the area above stays blank, hold the '
                              'lesson another way today and tell the office -- '
                              'the school needs its own video server.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (started != null)
              ValueListenableBuilder<DateTime>(
                valueListenable: now,
                builder: (context, tick, _) => _Clock(
                  clock: ClassClock(
                    openedAt: started,
                    now: tick,
                    scheduledMinutes: scheduledMinutes,
                  ),
                ),
              ),
            // Wrap, so a narrow phone stacks the controls instead of
            // clipping Leave off the edge.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: muted,
                  builder: (context, off, _) => OutlinedButton.icon(
                    onPressed: onMute,
                    icon: Icon(off ? Icons.mic_off : Icons.mic, size: 18),
                    label: Text(off ? 'Unmute' : 'Mute'),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: cameraOff,
                  builder: (context, off, _) => OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: Icon(off ? Icons.videocam_off : Icons.videocam,
                        size: 18),
                    label: Text(off ? 'Camera on' : 'Camera off'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onLeave,
                  icon: const Icon(Icons.call_end, size: 18),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  label: const Text('Leave'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Elapsed against the timetabled length, and what is left of it.
class _Clock extends StatelessWidget {
  final ClassClock clock;
  const _Clock({required this.clock});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('CLASS TIME',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
            const SizedBox(width: 10),
            Text(
              clock.scheduledLabel == null
                  ? clock.elapsedLabel
                  : '${clock.elapsedLabel} / ${clock.scheduledLabel}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (clock.progress != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clock.progress,
              minHeight: 4,
              // Red once the slot is used up. The class does not stop --
              // ending it is the teacher's decision, not a timer's --
              // but nobody should have to work out that they are over.
              color: clock.overrunning ? theme.colorScheme.error : null,
            ),
          ),
        if (clock.remainingLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            clock.remainingLabel!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: clock.overrunning ? theme.colorScheme.error : null,
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

/// What to say when the class cannot be held on this screen.
class _Fallback extends StatelessWidget {
  /// True when this platform normally embeds and this time could not --
  /// a blocked script, an engine that will not run it. Different from a
  /// phone build, where handing off is simply how it works, and the
  /// wording should not imply something is broken.
  final bool embedded;

  /// The platform ran the lesson in its own SDK. This screen is what is
  /// behind it, so the wording is "you are in the class" rather than
  /// "something went wrong".
  final bool native;
  final bool handedOff;

  /// What went wrong, in the words of the step it failed at. Empty when
  /// there is nothing to add.
  final String reason;
  final VoidCallback onOpen;

  const _Fallback({
    required this.embedded,
    required this.native,
    required this.handedOff,
    required this.reason,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_outlined, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                native
                    ? 'You have left the class'
                    : handedOff
                        ? 'The class is open'
                        : 'Join the class',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                native
                    ? 'The lesson is still going. Rejoin if you left by '
                        'accident, or go back when it is over.'
                    : handedOff
                        ? 'It opened outside LogicClass. Come back here when the '
                            'lesson is over.'
                        : embedded
                            // Names the deployment. When this card is
                            // what somebody reports, "which server
                            // would not start" is the first question,
                            // and it used to be unanswerable from the
                            // screenshot.
                            ? '${reason.isEmpty ? 'The video would not start.' : reason} '
                                'The lesson is still running -- try joining '
                                'it again.'
                            : 'The lesson opens in the Jitsi Meet app, or in '
                                'your browser if it is not installed.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(native || embedded ? Icons.videocam : Icons.open_in_new),
                label: Text(native
                    ? 'Rejoin the class'
                    : embedded
                        ? 'Try joining again'
                        : handedOff
                            ? 'Open it again'
                            : 'Join the class'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
