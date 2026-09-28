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

  /// Everybody in the lesson, drawn by this app.
  Widget view();
}
