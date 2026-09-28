import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/meeting/online_class_screen.dart';
import '../../../../core/meeting/passcode_prompt.dart';
import '../../../../core/router/app_router.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../controllers/class_session_controller.dart';

/// Where an invitation link lands.
///
/// ## What this screen is allowed to assume: nothing
///
/// The link is an address, not a permission. Anybody can follow one --
/// it gets forwarded into group chats and screenshotted -- so this
/// screen asks LogicClass for a pass exactly the way every other way in
/// does, and shows whatever answer comes back.
///
/// The server decides, in this order: the school from the caller's own
/// account, a line of their own in this lesson's register, the passcode
/// the teacher read out, and the section, grade, department and
/// programme they are in *now*. Four locks, and this screen holds none
/// of the keys. It cannot: it runs in a browser, on a device that may
/// have been handed to somebody else.
///
/// So there is deliberately no lookup here of what the lesson is before
/// the pass is asked for. Telling somebody "this is Grade 10 Physics
/// with Ms Santos" before finding out whether they belong in it would
/// leak the timetable to anybody holding a forwarded link.
class JoinByLinkScreen extends ConsumerStatefulWidget {
  final String schoolId;
  final String sessionId;

  const JoinByLinkScreen({
    super.key,
    required this.schoolId,
    required this.sessionId,
  });

  @override
  ConsumerState<JoinByLinkScreen> createState() => _JoinByLinkScreenState();
}

class _JoinByLinkScreenState extends ConsumerState<JoinByLinkScreen> {
  bool _asked = false;
  String? _refusal;

  @override
  void initState() {
    super.initState();
    // After the first frame: this pushes a dialog, and a dialog cannot
    // be opened while the screen that owns it is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (_asked) return;
    _asked = true;

    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) return;

    // A link from another school's deployment, pasted into this one.
    // Refused here rather than sent to a server that would refuse it,
    // because the message can be a better one.
    if (me.schoolId != null && me.schoolId != widget.schoolId) {
      setState(() => _refusal =
          'That invitation is for a different school. Sign in with the '
          'account that school gave you.');
      return;
    }

    MeetingPass? pass;
    final entered = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasscodePrompt(
        // Not the subject: naming the lesson before anybody has been
        // let into it tells whoever is holding a forwarded link what
        // the school is teaching and when.
        subject: 'this class',
        onJoin: (passcode) async {
          final tried = await ref
              .read(classSessionActionControllerProvider.notifier)
              .meetingToken(widget.sessionId, passcode: passcode);
          if (!tried.allowed) {
            return tried.refusal ?? 'You could not be let into the class.';
          }
          pass = tried;
          return null;
        },
      ),
    );

    if (!mounted) return;
    if (entered != true) {
      _goHome();
      return;
    }

    final room = pass?.room;
    if (room == null || room.isEmpty) {
      setState(() => _refusal =
          'That class is not online at the moment. Your teacher will '
          'start it when the lesson begins.');
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineClassScreen(
        room: room,
        // Named only now, when the person is already in. Until the pass
        // came back there was nothing safe to say.
        subject: 'Class',
        section: '',
        displayName: me.fullName,
        token: pass!.token,
        provider: pass!.provider,
        serverUrl: pass!.url,
        openedAt: DateTime.now(),
      ),
    ));
    if (mounted) _goHome();
  }

  void _goHome() {
    final me = ref.read(authStateProvider).valueOrNull;
    if (me == null) {
      context.go(AppRoutes.login);
      return;
    }
    context.go(AppRoutes.homeFor(me.role));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refusal = _refusal;

    return Scaffold(
      body: Center(
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
                Text(
                  refusal == null ? 'Joining the class' : 'You cannot join this class',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  refusal ??
                      'Enter the code your teacher read out at the start of '
                          'the lesson.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (refusal == null)
                  const CircularProgressIndicator()
                else
                  FilledButton(
                    onPressed: _goHome,
                    child: const Text('Go to my classes'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
