import 'package:flutter/widgets.dart';

import '../board_controller.dart';
import '../camera_setup.dart';
import '../whiteboard.dart';

/// The lesson's video, as the screen needs to talk to it.
///
/// A seam rather than a platform split. There is only one kind of call
/// now -- a media server, drawn by this app -- so this exists for one
/// reason: a widget test cannot open a camera, and every version of this
/// screen that could not be driven from a test shipped a bug that a test
/// would have caught. Twice it was a screen that believed something it
/// had never checked.
abstract class ClassroomCall {
  /// Why the last [join] failed, in the media server's own words.
  ///
  /// Shown on the failure card. The two ways this goes wrong look
  /// identical from the outside -- a server address that is `https://`
  /// where it should be `wss://`, and a key the server rejects -- and
  /// both produce "could not start". The underlying error names which,
  /// and a person configuring this should not have to open a browser
  /// console to find out.
  String? get lastError;

  /// Joins, and says whether it got in.
  Future<bool> join({
    required String url,
    required String token,
    required bool asModerator,
  });

  /// Hangs up. A participant left behind in a room nobody can see is a
  /// live microphone in somebody's house.
  Future<void> leave();

  Future<void> setMicrophone(bool on);
  Future<void> setCamera(bool on);

  /// Puts a window in front of the class, or takes it away.
  ///
  /// Returns what actually happened, which is not always what was
  /// asked: the browser shows its own chooser and a teacher who thinks
  /// better of it and cancels has not shared anything. A control that
  /// then sat there saying "Stop sharing" would be lying about the
  /// state of the lesson.
  Future<bool> setScreenShare(bool on);

  /// The cameras this device will hand over.
  Future<List<CameraOption>> cameras();

  /// Switches to one of them, mid-lesson, without rejoining.
  Future<void> useCamera(String deviceId);

  /// Asks the camera to blur what is behind the person, and says
  /// whether it did.
  ///
  /// Not an effect this app draws. It is a property of the camera,
  /// provided by the operating system, and most cameras do not have it
  /// -- so the answer is the camera's own and the screen reports it
  /// rather than assuming.
  Future<BackgroundSupport> setBackgroundBlur(bool on);

  /// Puts a board message on the wire, to everybody in the lesson.
  Future<void> sendBoardMessage(BoardMessage message);

  /// Hands the call the board, so that what arrives from the network
  /// reaches it and so that the video knows what to draw on top.
  void attachBoard(LessonBoard board);

  /// Everybody in the lesson, drawn by this app.
  Widget view();
}
