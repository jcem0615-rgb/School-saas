import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../board_controller.dart';
import '../camera_setup.dart';
import '../whiteboard.dart';
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

  /// Everything drawn on the lesson travels under this name, so a
  /// future feature that also sends data can tell its own messages from
  /// these without inspecting them.
  static const boardTopic = 'board';

  lk.EventsListener<lk.RoomEvent>? _events;
  LessonBoard? _board;

  @override
  String? lastError;

  @override
  Future<bool> join({
    required String url,
    required String token,
    required bool asModerator,
  }) async {
    try {
      lastError = null;
      await _room.connect(url, token);
      _listen(asModerator: asModerator);
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
      lastError = '$error';
      return false;
    }
  }

  void _listen({required bool asModerator}) {
    _events?.dispose();
    final events = _room.createListener();
    _events = events;

    events.on<lk.DataReceivedEvent>((event) {
      if (event.topic != boardTopic) return;
      final board = _board;
      if (board == null) return;
      try {
        board.receive(utf8.decode(event.data));
      } catch (error) {
        // Anything unreadable is dropped. This arrives from the network
        // in the middle of a lesson and must never end one.
        debugPrint('Unreadable board message: $error');
      }
    });

    if (asModerator) {
      events.on<lk.ParticipantConnectedEvent>((_) {
        // A pupil who joins ten minutes in would otherwise see a clean
        // slide with the teacher talking about a circle that is not
        // there. Only the teacher does this, so sixty arrivals do not
        // produce sixty copies of the board.
        _board?.resend();
      });
    }
  }

  @override
  Future<void> leave() async {
    await _events?.dispose();
    _events = null;
    await _room.disconnect();
  }

  @override
  Future<void> setMicrophone(bool on) async =>
      _room.localParticipant?.setMicrophoneEnabled(on);

  @override
  Future<void> setCamera(bool on) async =>
      _room.localParticipant?.setCameraEnabled(on);

  @override
  Future<bool> setScreenShare(bool on) async {
    try {
      await _room.localParticipant?.setScreenShareEnabled(on);
      // Read back rather than assume. The browser shows its own chooser
      // and a teacher who thinks better of it and cancels has shared
      // nothing -- a button that then said "Stop sharing" would be
      // lying about the state of the lesson.
      return _room.localParticipant?.isScreenShareEnabled() ?? false;
    } catch (error) {
      debugPrint('Screen share refused: $error');
      return _room.localParticipant?.isScreenShareEnabled() ?? false;
    }
  }

  @override
  Future<List<CameraOption>> cameras() async {
    try {
      final devices = await lk.Hardware.instance.videoInputs();
      return [
        for (final device in devices)
          CameraOption(id: device.deviceId, label: device.label),
      ];
    } catch (error) {
      debugPrint('No camera list: $error');
      return const [];
    }
  }

  @override
  Future<void> useCamera(String deviceId) async {
    final track = _localCamera;
    if (track == null) return;
    try {
      await track.switchCamera(deviceId);
    } catch (error) {
      // A camera unplugged between listing it and choosing it. The
      // lesson carries on with the one it already had.
      debugPrint('Could not switch camera: $error');
    }
  }

  @override
  Future<BackgroundSupport> setBackgroundBlur(bool on) async {
    final track = _localCamera?.mediaStreamTrack;
    if (track == null) return BackgroundSupport.unavailable;
    try {
      await track.applyConstraints({backgroundBlurSetting: on});
      // Believe the camera, not the request. Browsers accept this
      // constraint and then leave the picture exactly as it was.
      return backgroundAfterTrying(settings: track.getSettings(), wanted: on);
    } catch (error) {
      debugPrint('No background blur: $error');
      return BackgroundSupport.unavailable;
    }
  }

  @override
  Future<void> sendBoardMessage(BoardMessage message) async {
    try {
      await _room.localParticipant?.publishData(
        utf8.encode(encodeBoardMessage(message)),
        // Reliable: a stroke that goes missing leaves the class looking
        // at a circle round nothing, and a clearing that goes missing
        // leaves marks over the next slide.
        reliable: true,
        topic: boardTopic,
      );
    } catch (error) {
      debugPrint('Board message not sent: $error');
    }
  }

  @override
  void attachBoard(LessonBoard board) => _board = board;

  lk.LocalVideoTrack? get _localCamera => _room.localParticipant
      ?.getTrackPublicationBySource(lk.TrackSource.camera)
      ?.track as lk.LocalVideoTrack?;

  @override
  Widget view() => VideoGrid(room: _room, board: _board);
}
