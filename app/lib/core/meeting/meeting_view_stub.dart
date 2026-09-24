import 'package:flutter/material.dart';

/// Phone and desktop builds have nothing to embed.
///
/// The screen asks for this widget only when [MeetingSupport.embedded] is
/// reported, and the stub never reports it, so this is unreachable -- it
/// exists so the shared screen compiles on every platform.
Widget buildMeetingView(String room) => const SizedBox.shrink();

/// No script to load where there is no browser.
Future<bool> prepareMeetingView() async => false;

/// No element to wait for where there is no view.
Future<bool> awaitMeetingHost(String room) async => false;

/// Nothing is running, so nothing hangs up.
void disposeMeeting(String room) {}

/// Nothing to start.
bool startMeeting({
  required String room,
  required String displayName,
  required String subject,
  required bool asModerator,
  String? token,
}) =>
    false;

/// Nothing is running, so no command reaches anything.
void sendMeetingCommand(String room, String command) {}
