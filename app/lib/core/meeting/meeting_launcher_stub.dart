import 'dart:io' show Platform;

import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

import 'meeting_room.dart';

/// Everything that is not a browser.
///
/// On **Android and iOS** the lesson runs in the app: the Jitsi SDK puts
/// its own full-screen conference in front of the person, in the
/// LogicClass process, with no browser and no second app to install. The
/// screen behind it is still LogicClass and Leave comes back to it.
///
/// On **Windows, macOS and Linux** there is no such SDK, so the room is
/// handed to the operating system. That is a real difference and the
/// screen says so rather than implying otherwise.
class NativeMeetingLauncher extends MeetingLauncher {
  const NativeMeetingLauncher();

  /// Only the two platforms the plugin actually supports.
  ///
  /// Checked at runtime rather than by another conditional export: the
  /// package imports and compiles fine on desktop, it just has no
  /// implementation behind the method channel, so calling it there
  /// throws a MissingPluginException in front of a class.
  bool get _hasSdk => Platform.isAndroid || Platform.isIOS;

  @override
  MeetingSupport get support =>
      _hasSdk ? MeetingSupport.nativeSdk : MeetingSupport.handOff;

  @override
  Future<bool> handOff(
    String room, {
    required String displayName,
    String? token,
    bool muted = false,
  }) {
    // The name is passed so the class sees who joined rather than a grid
    // of "Fellow Sailor" -- Jitsi's random default, which in a lesson
    // that has to match names to faces is worse than useless. It used to
    // be pasted straight into the fragment, which a name with a space in
    // it -- most Filipino names -- turned into an invalid URL.
    final uri =
        Uri.parse(urlFor(room, displayName: displayName, token: token, muted: muted));
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<bool> joinInApp({
    required String room,
    required String displayName,
    required String subject,
    required bool asModerator,
  }) async {
    if (!_hasSdk) return false;
    try {
      await JitsiMeet().join(JitsiMeetConferenceOptions(
        serverURL: 'https://$meetingDomain',
        room: room,
        configOverrides: {
          'subject': subject,
          // Nobody is dropped into a lesson with a live microphone. The
          // teacher arrives able to speak; forty students opening at
          // once is how an online class starts badly.
          'startWithAudioMuted': !asModerator,
          'startWithVideoMuted': !asModerator,
          'prejoinPageEnabled': false,
          // Without this the SDK tries to bounce the person into the
          // standalone Jitsi app, which is the opposite of holding the
          // lesson inside this one.
          'disableDeepLinking': true,
        },
        featureFlags: {
          // No invite button. Who is in a lesson is decided by who is on
          // the register, and a share-link control in a child's hand is
          // the one thing that would undo that.
          'invite.enabled': false,
          'meeting-name.enabled': true,
          'calendar.enabled': false,
          'call-integration.enabled': false,
          'live-streaming.enabled': false,
          // Recording a class is a school decision with a consent
          // question behind it, not a button a student finds.
          'recording.enabled': false,
        },
        userInfo: JitsiMeetUserInfo(displayName: displayName),
      ));
      return true;
    } catch (_) {
      // A lesson is not worth a crash. False sends the screen to its
      // fallback, which offers to open the room outside the app.
      return false;
    }
  }
}

MeetingLauncher createMeetingLauncher() => const NativeMeetingLauncher();
