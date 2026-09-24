import 'dart:js_interop';
// For `callAsConstructor`: Jitsi's API is a constructor function on
// `window`, and constructing one is not in the typed half of the interop
// library.
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

import 'meeting_room.dart';

/// The browser build, where the lesson happens inside the app.
///
/// Jitsi is embedded through an `<iframe>` it drives itself: the page
/// loads `external_api.js` from the configured deployment and hands it a
/// parent element. That is the supported way to embed it, and it is the
/// reason this is Jitsi rather than Zoom or Meet -- both of those send
/// `X-Frame-Options`/`frame-ancestors` headers that refuse to be framed
/// at all, so "inside the app" for them can only ever mean a new tab.
///
/// Flutter draws to a canvas, so the iframe is a platform view sitting
/// in a hole punched through it. `registerViewFactory` is called once
/// per room, keyed by the room name, because a factory is registered for
/// the life of the page and re-registering the same id throws.
class BrowserMeetingLauncher extends MeetingLauncher {
  const BrowserMeetingLauncher();

  @override
  MeetingSupport get support => MeetingSupport.embedded;

  @override
  Future<bool> handOff(String room, {required String displayName}) async {
    // Reachable when a browser cannot run the embedded view -- the
    // script blocked, an unsupported engine. Opening a tab is worse than
    // staying in the app and better than missing the lesson.
    final opened = web.window.open(urlFor(room), '_blank');
    return opened != null;
  }
}

MeetingLauncher createMeetingLauncher() => const BrowserMeetingLauncher();

/// Ids already registered with the platform view registry this page.
final _registered = <String>{};

/// The view id for [room], registering its factory the first time.
String registerMeetingView(String room) {
  final viewId = 'jitsi-$room';
  if (_registered.add(viewId)) {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
      final host = web.document.createElement('div') as web.HTMLDivElement;
      host.id = viewId;
      host.style
        ..width = '100%'
        ..height = '100%'
        ..border = '0';
      return host;
    });
  }
  return viewId;
}

@JS('JitsiMeetExternalAPI')
external JSFunction? get _jitsiApiConstructor;

/// Loads Jitsi's script, once, and resolves when the constructor exists.
///
/// Returns false rather than throwing when it cannot be had: a script
/// that will not load is a lesson that has to happen in a browser tab,
/// and the screen offers that instead. A thrown error here would be a
/// red screen in front of a class.
Future<bool> ensureJitsiScript() async {
  if (_jitsiApiConstructor != null) return true;

  const id = 'jitsi-external-api';
  var script = web.document.getElementById(id) as web.HTMLScriptElement?;
  if (script == null) {
    script = web.document.createElement('script') as web.HTMLScriptElement;
    script.id = id;
    script.src = 'https://$meetingDomain/external_api.js';
    script.async = true;
    web.document.head!.append(script);
  }

  // Polled rather than driven by the load event, because the element may
  // already be in the document from a previous visit to this screen and
  // have fired its event long ago.
  for (var waited = 0; waited < 150; waited++) {
    if (_jitsiApiConstructor != null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Starts a meeting in the element registered for [room].
///
/// Returns a handle whose `dispose` hangs up. Leaving the screen has to
/// end the call: an iframe removed from the page while its conference is
/// still joined leaves a child in a room nobody can see them in.
JitsiCall? startJitsi({
  required String room,
  required String displayName,
  required String subject,
  required bool asModerator,
}) {
  final api = _jitsiApiConstructor;
  if (api == null) return null;

  final options = <String, Object?>{
    'roomName': room,
    'parentNode': web.document.getElementById('jitsi-$room'),
    'userInfo': {'displayName': displayName},
    'configOverwrite': {
      'subject': subject,
      // The class is the lesson, not a social call: nobody is dropped
      // into it with a live microphone.
      'startWithAudioMuted': !asModerator,
      'startWithVideoMuted': !asModerator,
      'prejoinPageEnabled': false,
      'disableDeepLinking': true,
    },
    'interfaceConfigOverwrite': {
      // No invite button. Who is in a lesson is decided by who is on the
      // register, and a share-link button in a child's hand is the one
      // control that would undo that.
      'TOOLBAR_BUTTONS': <String>[
        'microphone', 'camera', 'desktop', 'fullscreen', 'hangup',
        'chat', 'raisehand', 'tileview', 'settings',
      ],
      'SHOW_JITSI_WATERMARK': false,
      'MOBILE_APP_PROMO': false,
    },
  };

  final instance = api.callAsConstructor<JSObject>(
    meetingDomain.toJS,
    options.jsify(),
  );
  return JitsiCall._(instance);
}

/// A running meeting.
extension type JitsiCall._(JSObject _api) implements JSObject {
  external void dispose();
  external void executeCommand(String command);
}
