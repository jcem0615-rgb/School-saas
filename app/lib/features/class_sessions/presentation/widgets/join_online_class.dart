import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/meeting/online_class_screen.dart';
import '../../../../core/meeting/passcode_prompt.dart';
import '../../domain/entities/class_session.dart';
import '../controllers/class_session_controller.dart';

/// Goes into a lesson, having first asked LogicClass for the pass.
///
/// The child is already signed in -- to this app -- so the video call is
/// told who they are rather than asking them. Without this a pupil meets
/// a sign-in page belonging to a company they have no account with, on
/// the way into their own school's lesson.
///
/// One function, deliberately. There are three doors into a lesson now
/// -- the banner when one is on, the Online Class tile, and an
/// invitation link -- and three copies of this is where a fix lands on
/// one of them and not the others.
///
/// The code is asked for every time rather than trying without one and
/// asking only when refused: a wasted round trip in front of a class is
/// a lesson somebody is late for, and reading a refusal to decide
/// whether it was about the code turns the words of an error message
/// into an interface.
Future<void> joinOnlineClass(
  BuildContext context,
  WidgetRef ref,
  SubjectAttendanceMark mark,
  String displayName,
) async {
  final room = mark.meetingRoom;
  if (room == null || room.isEmpty) return;

  MeetingPass? pass;
  final entered = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PasscodePrompt(
      subject: mark.subject,
      onJoin: (passcode) async {
        final tried = await ref
            .read(classSessionActionControllerProvider.notifier)
            .meetingToken(mark.sessionId, passcode: passcode);
        if (!tried.allowed) {
          return tried.refusal ?? 'You could not be let into the class.';
        }
        pass = tried;
        return null;
      },
    ),
  );
  if (entered != true || pass == null || !context.mounted) return;

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => OnlineClassScreen(
      room: room,
      subject: mark.subject,
      section: mark.section,
      // Their real name. A register that has to match faces to names
      // cannot do it against a grid of nicknames.
      displayName: displayName,
      token: pass!.token,
      provider: pass!.provider,
      serverUrl: pass!.url,
      // When the lesson started, from their own mark. The timetabled
      // length is not on it, so a student sees time elapsed and no
      // countdown -- the bell is the teacher's to keep.
      openedAt: mark.timeIn,
    ),
  ));
}
