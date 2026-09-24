import 'package:url_launcher/url_launcher.dart';

import 'meeting_room.dart';

/// Phone and desktop builds.
///
/// Hands the room to the operating system, which opens the Jitsi app
/// when it is installed and the browser when it is not. Not embedded,
/// and the screen says so rather than implying otherwise -- an in-app
/// meeting on these platforms wants a native video SDK, which is a
/// dependency to add deliberately and test on a real handset, not one to
/// slip in behind a seam.
///
/// This is that seam. Adding the SDK later means writing one more
/// implementation of [MeetingLauncher]; no screen changes.
class HandOffMeetingLauncher extends MeetingLauncher {
  const HandOffMeetingLauncher();

  @override
  MeetingSupport get support => MeetingSupport.handOff;

  @override
  Future<bool> handOff(String room, {required String displayName}) {
    // The name is passed so the class sees who joined rather than a grid
    // of "Fellow Sailor" -- Jitsi's random default, which in a register
    // that has to match names to faces is worse than useless.
    final uri = Uri.parse('${urlFor(room)}#userInfo.displayName="$displayName"');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

MeetingLauncher createMeetingLauncher() => const HandOffMeetingLauncher();
