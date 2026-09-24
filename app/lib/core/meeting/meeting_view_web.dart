import 'dart:async';
import 'dart:js_interop';

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

/// Waits until the class is actually in the room.
///
/// Constructing the API is not joining. Jitsi's constructor builds an
/// iframe and returns; whether the conference ever comes up is decided
/// afterwards, inside a frame this code cannot see into. A deployment
/// that refuses to be embedded -- `X-Frame-Options`, a
/// `frame-ancestors` policy -- fails exactly there, and the screen used
/// to call that success: a classroom with its clock running, its
/// controls live, and a dead grey rectangle where the lesson should be.
///
/// So the screen waits for Jitsi to say it is in. If it never does, the
/// room is treated as unreachable and the person is offered the tab,
/// which on a deployment that asks nobody to sign in still gets them
/// into the lesson.
Future<bool> awaitMeetingJoined(
  String room, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final call = _calls[room];
  if (call == null) return Future<bool>.value(false);

  final settled = Completer<bool>();
  void finish(bool joined) {
    if (!settled.isCompleted) settled.complete(joined);
  }

  call.addListener('videoConferenceJoined', ((JSObject _) => finish(true)).toJS);
  // Said by Jitsi when it knows itself that it failed. Faster than the
  // timeout and the common case on a deployment that is up but will not
  // have us.
  call.addListener('errorOccurred', ((JSObject _) => finish(false)).toJS);
  call.addListener('connectionFailed', ((JSObject _) => finish(false)).toJS);

  // Generous, because it is also the time a class on a school's
  // connection needs on a bad morning, and cutting a lesson off at five
  // seconds would be its own bug.
  Timer(timeout, () => finish(false));
  return settled.future;
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
