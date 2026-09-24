import 'package:flutter/widgets.dart';

import 'meeting_view_factory.dart';

/// Everything the classroom screen does to the meeting underneath it.
///
/// The four calls were top-level functions behind a conditional export,
/// which is the right shape for the platform split and the wrong shape
/// for a test: on the VM the export resolves to the stub, so the whole
/// embedded path -- the one that ships to every browser -- was
/// unreachable from a widget test. That is how a screen that could never
/// stop spinning passed a full suite.
///
/// This is the same functions with a seam in front of them. The default
/// delegates to the platform; a test passes its own and can drive the
/// order the screen calls them in, which is where the bug was.
abstract class MeetingSurface {
  const MeetingSurface();

  /// Loads whatever the platform needs before a meeting can start.
  Future<bool> prepare();

  /// Waits for the element [view] draws into to exist.
  ///
  /// Separate from [prepare] and from [start] because the order of these
  /// three is the contract: the view has to be in the page before the
  /// meeting is attached to it.
  Future<bool> awaitHost(String room);

  bool start({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
  });

  void leave(String room);

  void command(String room, String command);

  Widget view(String room);
}

/// The real one: whatever this platform's meeting view provides.
class PlatformMeetingSurface extends MeetingSurface {
  const PlatformMeetingSurface();

  @override
  Future<bool> prepare() => prepareMeetingView();

  @override
  Future<bool> awaitHost(String room) => awaitMeetingHost(room);

  @override
  bool start({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
  }) =>
      startMeeting(
        room: room,
        displayName: displayName,
        subject: subject,
        asModerator: asModerator,
      );

  @override
  void leave(String room) => disposeMeeting(room);

  @override
  void command(String room, String command) => sendMeetingCommand(room, command);

  @override
  Widget view(String room) => buildMeetingView(room);
}
