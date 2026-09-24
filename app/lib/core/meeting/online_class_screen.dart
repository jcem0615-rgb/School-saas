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
  bool _muted = false;
  bool _cameraOff = false;

  /// Ticks the class clock. One second, because the thing it shows is
  /// seconds.
  Timer? _tick;

  bool get _embeds => _launcher.support == MeetingSupport.embedded;
  bool get _native => _launcher.support == MeetingSupport.nativeSdk;

  @override
  void initState() {
    super.initState();
    if (_embeds) {
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
      final loaded = await _surface.prepare();
      if (!mounted) return;
      if (!loaded) {
        // The script did not come. A lesson is not worth a red screen --
        // the fallback below opens it in a tab.
        setState(() => _ready = false);
        return;
      }

      final host = await _surface.awaitHost(widget.room);
      if (!mounted) return;
      if (!host) {
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
        setState(() => _ready = false);
        return;
      }

      // Constructed is not joined. The iframe belongs to another origin
      // and a deployment that refuses to be embedded fails inside it,
      // where nothing here can see -- which is how a blocked frame came
      // to render as a furnished classroom with a dead grey rectangle
      // in the middle of it. Jitsi says when it is in; until it does,
      // this is still connecting.
      final joined = await _surface.awaitJoined(widget.room);
      if (!mounted) return;
      if (!joined) {
        // Take the dead frame out rather than leave it behind the
        // fallback card.
        _surface.leave(widget.room);
        setState(() => _ready = false);
        return;
      }

      _startClock();
      setState(() => _ready = true);
    } catch (error) {
      // Swallowed deliberately, and this is the safety net rather than
      // the fix: the failure above is now handled by value. Anything
      // still thrown here -- third-party script, a browser that will not
      // run it -- must land on the fallback, because the alternative is
      // the bug this commit exists for.
      debugPrint('The online class could not start: $error');
      if (!mounted) return;
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_embeds) _surface.leave(widget.room);
    super.dispose();
  }

  /// Starts the clock, once there is something to time.
  void _startClock() {
    if (_tick != null || widget.openedAt == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleMute() {
    _surface.command(widget.room, 'toggleAudio');
    setState(() => _muted = !_muted);
  }

  void _toggleCamera() {
    _surface.command(widget.room, 'toggleVideo');
    setState(() => _cameraOff = !_cameraOff);
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

  Future<void> _openOutside() async {
    final ok = await _launcher.handOff(widget.room, displayName: widget.displayName);
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
              clock: widget.openedAt == null
                  ? null
                  : ClassClock(
                      openedAt: widget.openedAt!,
                      now: DateTime.now(),
                      scheduledMinutes: widget.scheduledMinutes,
                    ),
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
              onOpen: _native ? _rejoinNative : _openOutside,
            )
          // The view is built while we are still connecting, not after.
          // It is what creates the element the meeting attaches to, so
          // leaving it out until the meeting had started was a circle
          // with no way in. The overlay is opaque, so a half-built
          // iframe is not on show underneath it.
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_embeds) _surface.view(widget.room),
                if (_ready == null) const _Connecting(),
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
  const _Connecting();

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
          ],
        ),
      ),
    );
  }
}

/// The lesson's own controls, and its clock.
class _ClassroomControls extends StatelessWidget {
  final ClassClock? clock;
  final bool muted;
  final bool cameraOff;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onLeave;

  const _ClassroomControls({
    required this.clock,
    required this.muted,
    required this.cameraOff,
    required this.onMute,
    required this.onCamera,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = clock;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c != null) ...[
              Row(
                children: [
                  Text('CLASS TIME',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(letterSpacing: 1.2)),
                  const SizedBox(width: 10),
                  Text(
                    c.scheduledLabel == null
                        ? c.elapsedLabel
                        : '${c.elapsedLabel} / ${c.scheduledLabel}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (c.progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: c.progress,
                    minHeight: 4,
                    // Red once the slot is used up. The class does not
                    // stop -- ending it is the teacher's decision, not a
                    // timer's -- but nobody should have to work out that
                    // they are over.
                    color: c.overrunning ? theme.colorScheme.error : null,
                  ),
                ),
              if (c.remainingLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  c.remainingLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.overrunning ? theme.colorScheme.error : null,
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
            // Wrap, so a narrow phone stacks the controls instead of
            // clipping Leave off the edge.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onMute,
                  icon: Icon(muted ? Icons.mic_off : Icons.mic, size: 18),
                  label: Text(muted ? 'Unmute' : 'Mute'),
                ),
                OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: Icon(cameraOff ? Icons.videocam_off : Icons.videocam,
                      size: 18),
                  label: Text(cameraOff ? 'Camera on' : 'Camera off'),
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
  final VoidCallback onOpen;

  const _Fallback({
    required this.embedded,
    required this.native,
    required this.handedOff,
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
                            ? 'The video would not start here. $meetingDomain '
                                'did not answer, or would not run inside the '
                                'app. Opening it in a new tab still gets you '
                                'into the lesson.'
                            : 'The lesson opens in the Jitsi Meet app, or in '
                                'your browser if it is not installed.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(native ? Icons.videocam : Icons.open_in_new),
                label: Text(native
                    ? 'Rejoin the class'
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
