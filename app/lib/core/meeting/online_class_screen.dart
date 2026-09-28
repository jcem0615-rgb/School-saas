import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../main.dart' show kDemoMode;
import 'class_clock.dart';
import 'demo_video.dart';
import 'meeting_room.dart';
import 'webrtc/classroom_call.dart';
import 'webrtc/livekit_call.dart';

/// The lesson, held in the app.
///
/// One shape: a media server forwards everybody's video and LogicClass
/// draws it. That is what carries a class of sixty -- one upload each
/// rather than one per classmate -- and what makes it genuinely in-app,
/// since there is no embedded page for a server to refuse.
///
/// The teacher arrives speaking; everybody else arrives muted. There is
/// no time limit: the lesson ends when the teacher ends it.
class OnlineClassScreen extends StatefulWidget {
  final String room;
  final String subject;
  final String section;
  final String displayName;

  /// The pass from `issueMeetingToken`. Without one there is no lesson:
  /// a media server that let anybody in would be a room of children
  /// reachable by anyone who guessed a name.
  final String? token;

  /// `livekit` when the school has a video server configured.
  final String provider;

  /// Where to connect. Comes with the pass rather than being compiled
  /// in, so a school can move servers without rebuilding the app.
  final String? serverUrl;

  /// The teacher: arrives speaking, and can remove somebody.
  final bool asModerator;

  /// When the register was opened, for the clock.
  final DateTime? openedAt;

  /// Stands in for a real call, which a widget test cannot make.
  @visibleForTesting
  final ClassroomCall? debugCall;

  /// Stands in for the demo endpoint's description of itself.
  @visibleForTesting
  final Future<String?> Function()? debugConfiguration;

  const OnlineClassScreen({
    super.key,
    required this.room,
    required this.subject,
    required this.section,
    required this.displayName,
    this.token,
    this.provider = 'none',
    this.serverUrl,
    this.asModerator = false,
    this.openedAt,
    this.debugCall,
    this.debugConfiguration,
  });

  @override
  State<OnlineClassScreen> createState() => _OnlineClassScreenState();
}

enum _Phase { connecting, live, failed, notConfigured }

class _OnlineClassScreenState extends State<OnlineClassScreen> {
  late final ClassroomCall _call = widget.debugCall ?? LiveKitCall();

  late _Phase _phase;

  /// Notifiers, never setState, for anything that changes while the
  /// lesson runs. Rebuilding this screen tears the video out from under
  /// the class -- which is what a one-second clock on setState did.
  final _now = ValueNotifier(DateTime.now());
  final _micOn = ValueNotifier(false);
  final _cameraOn = ValueNotifier(true);
  Timer? _tick;

  /// What the demo's token endpoint says it holds, once a join has
  /// failed and somebody needs to know why. Empty until then, and on a
  /// real deployment it stays empty -- a school's teacher can do
  /// nothing with it and should not be shown it.
  final _configuration = ValueNotifier<String?>(null);

  bool get _configured =>
      schoolHasVideo(widget.provider, widget.serverUrl) &&
      (widget.token?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _micOn.value = widget.asModerator;
    _phase = _configured ? _Phase.connecting : _Phase.notConfigured;
    if (_configured) _join();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _now.dispose();
    _micOn.dispose();
    _cameraOn.dispose();
    _configuration.dispose();
    unawaited(_call.leave());
    super.dispose();
  }

  Future<void> _join() async {
    final joined = await _call.join(
      url: widget.serverUrl!,
      token: widget.token!,
      asModerator: widget.asModerator,
    );
    if (!mounted) return;
    if (!joined) {
      setState(() => _phase = _Phase.failed);
      unawaited(_describeConfiguration());
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _now.value = DateTime.now();
    });
    setState(() => _phase = _Phase.live);
  }

  Future<void> _retry() async {
    _configuration.value = null;
    setState(() => _phase = _Phase.connecting);
    await _join();
  }

  /// Asks the demo's endpoint what it holds, and puts the answer on the
  /// card.
  ///
  /// `invalid token` is the one failure that endpoint cannot see while
  /// minting: the three values are present, so it signs, and only
  /// LiveKit knows they are wrong. A GET on it names the ones that are
  /// the wrong shape and prints no value -- but only if somebody goes
  /// and opens it, and the person holding a failed demo should not have
  /// to. A notifier, not setState: the rest of this screen does not
  /// move for anything that arrives late.
  Future<void> _describeConfiguration() async {
    if (!kDemoMode) return;
    final summary = await (widget.debugConfiguration ??
        DemoVideo.configurationSummary)();
    if (mounted) _configuration.value = summary;
  }

  void _toggleMic() {
    _micOn.value = !_micOn.value;
    unawaited(_call.setMicrophone(_micOn.value));
  }

  void _toggleCamera() {
    _cameraOn.value = !_cameraOn.value;
    unawaited(_call.setCamera(_cameraOn.value));
  }

  Future<void> _leave() async {
    await _call.leave();
    if (mounted) await Navigator.of(context).maybePop();
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
      bottomNavigationBar: _phase == _Phase.live
          ? _Controls(
              openedAt: widget.openedAt,
              now: _now,
              micOn: _micOn,
              cameraOn: _cameraOn,
              onMic: _toggleMic,
              onCamera: _toggleCamera,
              onLeave: _leave,
            )
          : null,
      body: switch (_phase) {
        // The call is built once and kept. Rebuilding the subtree that
        // holds it is how a working lesson gets disconnected.
        _Phase.live => _call.view(),
        _Phase.connecting => const _Connecting(),
        _Phase.failed => _Message(
            title: 'The class could not start',
            body: 'The video server did not let this device in. The lesson '
                'is still running -- try joining it again.',
            // The server's own words, so the two ways this goes wrong
            // are told apart without opening a browser console: an
            // address that is https where it should be wss, and a key
            // the server rejects, both read as "could not start".
            detail: _call.lastError,
            // What the endpoint says it holds, when it has said it.
            // Only a demo ever fills this in.
            footnote: _configuration,
            action: 'Try joining again',
            onAction: _retry,
          ),
        _Phase.notConfigured => _Message(
            title: kDemoMode
                // Not "not part of the demo": it can be, and on a demo
                // with a video server behind it, it is. What is true is
                // that this one has not had it switched on -- which is
                // also what the body says, and the two should not
                // disagree on the same card.
                ? 'Live video is not switched on'
                : 'Online classes are not set up',
            body: videoNotConfigured(demo: kDemoMode),
          ),
      },
    );
  }
}

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
            Text('Joining the class', style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

/// Anything the screen has to say instead of a lesson.
class _Message extends StatelessWidget {
  final String title;
  final String body;

  /// What the thing underneath actually said. Small and quiet: it is
  /// for whoever is configuring this, not for the class.
  final String? detail;

  /// A line that arrives after the card does -- the demo endpoint's
  /// description of what it holds. A listenable rather than a String
  /// because it lands a moment later, and because nothing on this
  /// screen is allowed to rebuild through setState.
  final ValueListenable<String?>? footnote;
  final String? action;
  final VoidCallback? onAction;

  const _Message({
    required this.title,
    required this.body,
    this.detail,
    this.footnote,
    this.action,
    this.onAction,
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
              Icon(Icons.videocam_outlined,
                  size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  detail!,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (footnote != null)
                ValueListenableBuilder<String?>(
                  valueListenable: footnote!,
                  builder: (context, summary, _) {
                    if (summary == null || summary.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        summary,
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(action!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The lesson's own controls, and its clock.
///
/// Listens to notifiers so a tick or a button rebuilds this bar and
/// nothing else. The video must not sit in a subtree a second hand can
/// rebuild.
class _Controls extends StatelessWidget {
  final DateTime? openedAt;
  final ValueListenable<DateTime> now;
  final ValueListenable<bool> micOn;
  final ValueListenable<bool> cameraOn;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onLeave;

  const _Controls({
    required this.openedAt,
    required this.now,
    required this.micOn,
    required this.cameraOn,
    required this.onMic,
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
            if (started != null) ...[
              ValueListenableBuilder<DateTime>(
                valueListenable: now,
                builder: (context, tick, _) => Row(
                  children: [
                    Text('CLASS TIME',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(letterSpacing: 1.2)),
                    const SizedBox(width: 10),
                    Text(
                      ClassClock(openedAt: started, now: tick).elapsedLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: micOn,
                  builder: (context, on, _) => OutlinedButton.icon(
                    onPressed: onMic,
                    icon: Icon(on ? Icons.mic : Icons.mic_off, size: 18),
                    label: Text(on ? 'Mute' : 'Unmute'),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: cameraOn,
                  builder: (context, on, _) => OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: Icon(on ? Icons.videocam : Icons.videocam_off,
                        size: 18),
                    label: Text(on ? 'Camera off' : 'Camera on'),
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
