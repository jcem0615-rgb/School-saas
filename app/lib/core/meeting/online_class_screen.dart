import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'class_clock.dart';
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
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _now.value = DateTime.now();
    });
    setState(() => _phase = _Phase.live);
  }

  Future<void> _retry() async {
    setState(() => _phase = _Phase.connecting);
    await _join();
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
            action: 'Try joining again',
            onAction: _retry,
          ),
        _Phase.notConfigured => const _Message(
            title: 'Online classes are not set up',
            body: videoNotConfigured,
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
  final String? action;
  final VoidCallback? onAction;

  const _Message({
    required this.title,
    required this.body,
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
