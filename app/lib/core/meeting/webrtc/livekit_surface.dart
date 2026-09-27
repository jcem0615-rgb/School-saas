import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../meeting_surface.dart';
import 'peer_etiquette.dart';
import 'video_grid.dart';

/// A class held through a media server, drawn by this app.
///
/// The point of it, twice over.
///
/// **It carries a class.** A direct call between browsers has everybody
/// sending their own video to everybody else: six people is five uploads
/// each, sixty is fifty-nine from one laptop, and that does not go
/// slowly, it fails. A media server takes one stream from each person
/// and forwards it, so sixty costs a participant what six does.
///
/// **Nothing can refuse to embed it.** The lesson is Flutter widgets
/// over video tracks. There is no iframe, so there is no third-party
/// document, so there is no `X-Frame-Options` to be turned away by --
/// which is the wall that two public Jitsi deployments put this whole
/// feature into, and no amount of client code got past.
class LiveKitMeetingSurface extends MeetingSurface {
  /// The media server, `wss://...`, from the same callable that issued
  /// the pass. Never compiled in: which server holds a school's lessons
  /// is the school's decision and can change without a release.
  final String url;

  LiveKitMeetingSurface({required this.url});

  /// Both of these default to off, and a class of sixty does not work
  /// without them.
  ///
  /// `adaptiveStream` makes this device subscribe at the size it is
  /// actually drawing and stop subscribing to tiles that are off
  /// screen -- without it, sixty participants means sixty full streams
  /// decoded at once on a school laptop, which is not slow, it is a
  /// frozen machine. `dynacast` stops the *sending* side publishing
  /// quality layers nobody is looking at, which is the same saving
  /// taken off a teacher's upload.
  final _room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  lk.EventsListener<lk.RoomEvent>? _events;
  Completer<bool>? _connected;

  /// Mirrored rather than read back: a control that waits for a round
  /// trip before it looks pressed feels broken on a school connection.
  var _micOn = true;
  var _cameraOn = true;

  @override
  Future<bool> prepare() async => true;

  /// Nothing to wait for. The Jitsi path needed a DOM element to exist
  /// before the meeting could attach to it; this draws itself.
  @override
  Future<bool> awaitHost(String room) async => true;

  @override
  bool start({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
    String? token,
  }) {
    // No token, no lesson. Unlike the embedded path there is no
    // unauthenticated fallback here, and that is correct: a media
    // server that let anybody in would be a room full of children
    // reachable by anyone who guessed a name.
    if (token == null || token.isEmpty) return false;

    final settled = Completer<bool>();
    _connected = settled;

    _events = _room.createListener()
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!settled.isCompleted) settled.complete(false);
      });

    unawaited(() async {
      try {
        await _room.connect(url, token);
        // The teacher arrives speaking; everybody else arrives quiet.
        // Sixty microphones opening at once is how an online lesson
        // starts badly.
        _micOn = asModerator;
        _cameraOn = asModerator;
        await _room.localParticipant?.setMicrophoneEnabled(_micOn);
        await _room.localParticipant?.setCameraEnabled(_cameraOn);
        if (!settled.isCompleted) settled.complete(true);
      } catch (error) {
        debugPrint('The class could not be joined: $error');
        if (!settled.isCompleted) settled.complete(false);
      }
    }());

    return true;
  }

  @override
  Future<bool> awaitJoined(String room, {void Function()? onAlive}) async {
    final joined = await (_connected?.future ?? Future<bool>.value(false));
    if (joined) onAlive?.call();
    return joined;
  }

  @override
  void leave(String room) {
    // Hangs up before the screen goes away. A participant left behind
    // in a room nobody can see is a microphone in a house, live.
    unawaited(_events?.dispose());
    unawaited(_room.disconnect());
  }

  @override
  void command(String room, String command) {
    final me = _room.localParticipant;
    if (me == null) return;
    switch (command) {
      case 'toggleAudio':
        _micOn = !_micOn;
        unawaited(me.setMicrophoneEnabled(_micOn));
      case 'toggleVideo':
        _cameraOn = !_cameraOn;
        unawaited(me.setCameraEnabled(_cameraOn));
      case 'hangup':
        leave(room);
    }
  }

  @override
  Widget view(String room) => VideoGrid(room: _room);

  /// What the screen tells a class about how many will fit.
  MeetingTransport get transport => MeetingTransport.forwarded;
}
