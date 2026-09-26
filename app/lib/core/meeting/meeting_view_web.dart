import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'meeting_launcher_web.dart';
import 'meeting_room.dart';

/// The hole in the canvas the meeting is drawn into.
///
/// `HtmlElementView` is how a Flutter web app puts a real DOM element on
/// screen; Jitsi needs one to attach its iframe to, and Flutter otherwise
/// paints everything to a single canvas with no DOM to speak of.
Widget buildMeetingView(String room) =>
    HtmlElementView(viewType: registerMeetingView(room));

Future<bool> prepareMeetingView() => ensureJitsiScript();

Future<bool> awaitMeetingHost(String room) => awaitJitsiHost(room);

/// Live calls, so leaving the screen can hang up the right one.
final _calls = <String, JitsiCall>{};

bool startMeeting({
  required String room,
  required String displayName,
  required String subject,
  required bool asModerator,
  String? token,
}) {
  if (_calls.containsKey(room)) return true;
  final call = startJitsi(
    room: room,
    displayName: displayName,
    subject: subject,
    asModerator: asModerator,
    token: token,
  );
  if (call == null) return false;
  _calls[room] = call;
  return true;
}

/// Rooms this page has been in. See [awaitMeetingJoined].
final _joined = <String>{};

/// The events that mean the frame is alive, whatever else is true.
///
/// Not an exhaustive list and does not need to be: one of anything is
/// proof that Jitsi is running in there, which is the only question
/// being asked.
const _signsOfLife = <String>[
  'browserSupport',
  'participantJoined',
  'participantRoleChanged',
  'audioMuteStatusChanged',
  'videoMuteStatusChanged',
  'audioAvailabilityChanged',
  'videoAvailabilityChanged',
];

/// Waits until the class is in the room, or until the frame proves dead.
///
/// Constructing the API is not joining. Jitsi's constructor builds an
/// iframe and returns; whether the conference comes up is decided
/// afterwards, inside a frame belonging to another origin that nothing
/// here can see into.
///
/// The first version of this waited twenty seconds for
/// `videoConferenceJoined` and tore the call down if it had not arrived.
/// That killed lessons that were simply slow -- a cold room on a distant
/// server, from a school's connection -- and what the class saw was
/// Jitsi announcing it had been disconnected, which it had, by us.
///
/// So it now asks the question that can actually be answered from out
/// here: has anything happened in there at all. A blocked frame is
/// silent -- no event of any kind, ever -- and that is worth taking
/// down. A frame that has spoken once is alive and is Jitsi's to manage;
/// its own reconnection notice is a better thing to put in front of a
/// class than a screen that gives up on the lesson.
Future<bool> awaitMeetingJoined(
  String room, {
  void Function()? onAlive,
  Duration silence = const Duration(seconds: 12),
  Duration join = const Duration(seconds: 90),
}) {
  // Already in this room. Re-entering the screen -- backing out and
  // going in again, which a teacher does -- finds the call still
  // running, and `videoConferenceJoined` does not fire twice. Waiting
  // for it again would time out and dispose a conference the class is
  // sitting in.
  if (_joined.contains(room)) return Future<bool>.value(true);

  final call = _calls[room];
  if (call == null) return Future<bool>.value(false);

  final settled = Completer<bool>();
  var alive = false;
  void finish(bool joined) {
    if (!settled.isCompleted) settled.complete(joined);
  }

  // The moment the frame speaks, it should be what the class is looking
  // at. Jitsi draws its own connecting state, and its own account of
  // what is happening is better than an opaque overlay of ours sitting
  // on top of a working call for another minute.
  void breathing() {
    if (alive) return;
    alive = true;
    onAlive?.call();
  }

  for (final event in _signsOfLife) {
    call.addListener(event, ((JSObject _) => breathing()).toJS);
  }

  call.addListener('videoConferenceJoined', ((JSObject _) {
    breathing();
    _joined.add(room);
    finish(true);
  }).toJS);

  // Only fatal before there is any sign of life. Once the conference is
  // running, an error is Jitsi's to recover from -- it reconnects on its
  // own, and ending the call on its behalf is what this whole comment
  // is about.
  for (final event in const ['errorOccurred', 'connectionFailed']) {
    call.addListener(event, ((JSObject _) {
      if (!alive) finish(false);
    }).toJS);
  }

  // Silent this long and nothing is coming: the frame was refused.
  Timer(silence, () {
    if (!alive) finish(false);
  });
  // Alive but still not joined after this: show the classroom anyway and
  // let Jitsi say what is happening. Ninety seconds is far longer than a
  // join needs and is not a deadline the lesson is held to -- it is the
  // point at which this stops watching.
  Timer(join, () => finish(meetingIsWorthKeeping(anySignal: alive, joined: false)));

  return settled.future;
}

/// Hangs up and tears the iframe down./// Hangs up and tears the iframe down.
///
/// Called from the screen's dispose, and it has to be: an iframe removed
/// from the page with its conference still joined leaves a child in a
/// room nobody can see them in, microphone live, until the tab is
/// closed.
void disposeMeeting(String room) {
  _joined.remove(room);
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
