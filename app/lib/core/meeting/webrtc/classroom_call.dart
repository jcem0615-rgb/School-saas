import 'package:flutter/widgets.dart';

/// The lesson's video, as the screen needs to talk to it.
///
/// A seam rather than a platform split. There is only one kind of call
/// now -- a media server, drawn by this app -- so this exists for one
/// reason: a widget test cannot open a camera, and every version of this
/// screen that could not be driven from a test shipped a bug that a test
/// would have caught. Twice it was a screen that believed something it
/// had never checked.
abstract class ClassroomCall {
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

  /// Everybody in the lesson, drawn by this app.
  Widget view();
}
