import 'package:flutter/material.dart';

import 'meeting_launcher_factory.dart';
import 'meeting_view_factory.dart';

/// The lesson, held in the app.
///
/// One screen for both sides of the class: the teacher arrives as the
/// moderator with their camera on, the students muted, because forty
/// microphones opening at once is how an online lesson starts badly.
///
/// What it does depends on what the platform can do, and it says which
/// rather than pretending. In a browser the meeting renders here. On a
/// phone build it hands the room to the device -- the Jitsi app if it is
/// installed, the browser if not -- because embedding video on a handset
/// wants a native SDK, and that is a dependency to add deliberately and
/// test on a real device rather than slip in behind a seam. The seam is
/// built; adding it later changes this file not at all.
class OnlineClassScreen extends StatefulWidget {
  final String room;
  final String subject;
  final String section;
  final String displayName;

  /// The teacher, who starts un-muted and can end the call for everyone.
  final bool asModerator;

  const OnlineClassScreen({
    super.key,
    required this.room,
    required this.subject,
    required this.section,
    required this.displayName,
    this.asModerator = false,
  });

  @override
  State<OnlineClassScreen> createState() => _OnlineClassScreenState();
}

class _OnlineClassScreenState extends State<OnlineClassScreen> {
  final _launcher = createMeetingLauncher();

  /// Null while we are still finding out.
  bool? _ready;
  bool _handedOff = false;

  bool get _embeds => _launcher.support == MeetingSupport.embedded;

  @override
  void initState() {
    super.initState();
    if (_embeds) {
      _start();
    } else {
      _ready = false;
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
    setState(() => _ready = started);
  }

  @override
  void dispose() {
    if (_embeds) disposeMeeting(widget.room);
    super.dispose();
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
      body: switch (_ready) {
        null => const Center(child: CircularProgressIndicator()),
        true => buildMeetingView(widget.room),
        false => _Fallback(
            embedded: _embeds,
            handedOff: _handedOff,
            onOpen: _openOutside,
          ),
      },
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
  final bool handedOff;
  final VoidCallback onOpen;

  const _Fallback({
    required this.embedded,
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
                handedOff ? 'The class is open' : 'Join the class',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                handedOff
                    ? 'It opened outside LogicClass. Come back here when the '
                        'lesson is over.'
                    : embedded
                        ? 'The video could not start on this screen. Opening it '
                            'in a new tab will still get you into the lesson.'
                        : 'The lesson opens in the Jitsi Meet app, or in your '
                            'browser if it is not installed.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: Text(handedOff ? 'Open it again' : 'Join the class'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
