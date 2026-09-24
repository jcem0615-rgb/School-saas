import 'package:flutter/material.dart';

import 'dart:async';

import 'class_clock.dart';
import 'meeting_launcher_factory.dart';
import 'meeting_view_factory.dart';

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

  /// When the teacher pressed Time In, and how long the timetable says
  /// this class is. Both optional: the classroom works without a clock,
  /// it just cannot show one.
  final DateTime? openedAt;
  final int? scheduledMinutes;

  const OnlineClassScreen({
    super.key,
    required this.room,
    required this.subject,
    required this.section,
    required this.displayName,
    this.asModerator = false,
    this.openedAt,
    this.scheduledMinutes,
  });

  @override
  State<OnlineClassScreen> createState() => _OnlineClassScreenState();
}

class _OnlineClassScreenState extends State<OnlineClassScreen> {
  final _launcher = createMeetingLauncher();

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
    final loaded = await prepareMeetingView();
    if (!mounted) return;
    if (!loaded) {
      // The script did not come. A lesson is not worth a red screen --
      // the fallback below opens it in a tab.
      setState(() => _ready = false);
      return;
    }
    // One frame, so the platform view exists before Jitsi is handed it.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final started = startMeeting(
      room: widget.room,
      displayName: widget.displayName,
      subject: '${widget.subject} - ${widget.section}',
      asModerator: widget.asModerator,
    );
    if (started) _startClock();
    setState(() => _ready = started);
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_embeds) disposeMeeting(widget.room);
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
    sendMeetingCommand(widget.room, 'toggleAudio');
    setState(() => _muted = !_muted);
  }

  void _toggleCamera() {
    sendMeetingCommand(widget.room, 'toggleVideo');
    setState(() => _cameraOff = !_cameraOff);
  }

  void _leave() {
    // Hangs up before popping. Popping alone tears the iframe out of the
    // page with the conference still joined, which leaves somebody in a
    // room nobody can see them in.
    sendMeetingCommand(widget.room, 'hangup');
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
      body: switch (_ready) {
        null => const Center(child: CircularProgressIndicator()),
        true => buildMeetingView(widget.room),
        false => _Fallback(
            embedded: _embeds,
            native: _native,
            handedOff: _handedOff,
            onOpen: _native ? _rejoinNative : _openOutside,
          ),
      },
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
                            ? 'The video could not start on this screen. Opening '
                                'it in a new tab will still get you into the '
                                'lesson.'
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
