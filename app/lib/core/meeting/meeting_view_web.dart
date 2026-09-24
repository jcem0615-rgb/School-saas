import 'package:flutter/material.dart';

import 'meeting_launcher_web.dart';

/// The hole in the canvas the meeting is drawn into.
///
/// `HtmlElementView` is how a Flutter web app puts a real DOM element on
/// screen; Jitsi needs one to attach its iframe to, and Flutter otherwise
/// paints everything to a single canvas with no DOM to speak of.
Widget buildMeetingView(String room) =>
    HtmlElementView(viewType: registerMeetingView(room));

Future<bool> prepareMeetingView() => ensureJitsiScript();

/// Live calls, so leaving the screen can hang up the right one.
final _calls = <String, JitsiCall>{};

bool startMeeting({
  required String room,
  required String displayName,
  required String subject,
  required bool asModerator,
}) {
  if (_calls.containsKey(room)) return true;
  final call = startJitsi(
    room: room,
    displayName: displayName,
    subject: subject,
    asModerator: asModerator,
  );
  if (call == null) return false;
  _calls[room] = call;
  return true;
}

/// Hangs up and tears the iframe down.
///
/// Called from the screen's dispose, and it has to be: an iframe removed
/// from the page with its conference still joined leaves a child in a
/// room nobody can see them in, microphone live, until the tab is
/// closed.
void disposeMeeting(String room) {
  _calls.remove(room)?.dispose();
}

/// Drives the running call from the app's own controls.
///
/// The buttons in the classroom are Flutter, the call is Jitsi's, and
/// this is the join between them. Silently does nothing when the room
/// is not running -- a control that throws because the call already
/// ended is worse than one that does nothing.
void sendMeetingCommand(String room, String command) {
  _calls[room]?.executeCommand(command);
}
