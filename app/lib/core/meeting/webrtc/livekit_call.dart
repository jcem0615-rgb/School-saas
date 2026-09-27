import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'classroom_call.dart';
import 'video_grid.dart';

/// A class held through a media server.
///
/// Everybody sends one stream to the server, which forwards it, so a
/// class of sixty costs a participant what a call of six does. And the
/// video is drawn by this app in its own widgets -- there is no embedded
/// page, so there is no document for a server to refuse, which is what
/// ended the previous approach.
class LiveKitCall implements ClassroomCall {
  /// Both default to off in the library, and a class of sixty does not
  /// work without them.
  ///
  /// `adaptiveStream` makes this device subscribe at the size it is
  /// actually drawing and stop subscribing to tiles that have scrolled
  /// off screen. Without it, sixty participants is sixty full-resolution
  /// streams decoded at once on a school laptop -- not slow, frozen.
  /// `dynacast` stops the sending side publishing quality layers nobody
  /// is looking at, which is the same saving taken off an upload.
  final _room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );

  @override
  Future<bool> join({
    required String url,
    required String token,
    required bool asModerator,
  }) async {
    try {
      await _room.connect(url, token);
      // The teacher arrives speaking and visible. Everybody else
      // arrives quiet: sixty microphones opening at once is how an
      // online lesson starts badly. Cameras are on for everyone,
      // because a register that has to match faces to names cannot do
      // it against a grid of initials.
      await _room.localParticipant?.setMicrophoneEnabled(asModerator);
      await _room.localParticipant?.setCameraEnabled(true);
      return true;
    } catch (error) {
      // Includes the person refusing the camera prompt, which is not an
      // error the class should be ejected for -- but at this point
      // there is no connection either, so it is one answer.
      debugPrint('The class could not be joined: $error');
      return false;
    }
  }

  @override
  Future<void> leave() => _room.disconnect();

  @override
  Future<void> setMicrophone(bool on) async =>
      _room.localParticipant?.setMicrophoneEnabled(on);

  @override
  Future<void> setCamera(bool on) async =>
      _room.localParticipant?.setCameraEnabled(on);

  @override
  Widget view() => VideoGrid(room: _room);
}
