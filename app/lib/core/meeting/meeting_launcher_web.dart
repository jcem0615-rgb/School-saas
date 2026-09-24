import 'dart:js_interop';
// For `callAsConstructor`: Jitsi's API is a constructor function on
// `window`, and constructing one is not in the typed half of the interop
// library.
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show debugPrint;

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
  Future<bool> handOff(
    String room, {
    required String displayName,
    String? token,
    bool muted = false,
  }) async {
    // Reachable when a browser cannot run the embedded view -- the
    // script blocked, an unsupported engine. Opening a tab is worse than
    // staying in the app and better than missing the lesson.
    final opened = web.window.open(
      urlFor(room, displayName: displayName, token: token, muted: muted),
      '_blank',
    );
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
  if (script != null) {
    // A previous visit already tried and the script never arrived --
    // a filtered connection, a blocked domain. Waiting ten seconds
    // again to reach the same answer is ten seconds of a class staring
    // at a spinner.
    if (script.getAttribute('data-failed') == '1') return false;
  } else {
    script = web.document.createElement('script') as web.HTMLScriptElement;
    script.id = id;
    script.src = 'https://$meetingDomain/external_api.js';
    script.async = true;
    // Marked on the element rather than held in a variable, because the
    // next visit to this screen gets a new closure and the same DOM.
    script.addEventListener(
      'error',
      ((web.Event _) => script!.setAttribute('data-failed', '1')).toJS,
    );
    web.document.head!.append(script);
  }

  // Polled rather than driven by the load event, because the element may
  // already be in the document from a previous visit to this screen and
  // have fired its event long ago.
  for (var waited = 0; waited < 100; waited++) {
    if (_jitsiApiConstructor != null) return true;
    if (script.getAttribute('data-failed') == '1') return false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Waits for the platform view's host element to exist in the document.
///
/// This is the half that was missing, and it is why the screen spun
/// forever. Flutter creates the `<div>` when it builds the
/// `HtmlElementView`, a frame or more after the widget is asked for, so
/// "the screen has decided to show the meeting" and "the element Jitsi
/// attaches to is in the page" are not the same moment. Handing Jitsi a
/// null parentNode throws inside its constructor, and a throw in an
/// un-awaited start is a spinner that never stops.
Future<bool> awaitJitsiHost(String room) async {
  for (var waited = 0; waited < 50; waited++) {
    if (web.document.getElementById('jitsi-$room') != null) return true;
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
  String? token,
}) {
  final api = _jitsiApiConstructor;
  if (api == null) return null;

  // The element the meeting is drawn into. Null means the platform view
  // has not been built yet, and constructing against null is what hung
  // this screen: Jitsi's constructor appends to the node it is given,
  // throws on null, and the throw escaped an un-awaited start, so the
  // spinner never came down. Refusing here turns that into the fallback,
  // which at least gets the class into the lesson.
  final host = web.document.getElementById('jitsi-$room');
  if (host == null) return null;

  final options = <String, Object?>{
    'roomName': room,
    'parentNode': host,
    'userInfo': {'displayName': displayName},
    // The whole of the sign-in, answered before it is asked. LogicClass
    // already knows who this is -- they signed in to it -- so it says
    // so in a token the deployment accepts, and nobody is sent to
    // Google to prove they are allowed into their own school's lesson.
    // Null on a school that has configured no key, which joins the way
    // it always did.
    if (token != null) 'jwt': token,
    'configOverwrite': {
      'subject': subject,
      // The class is the lesson, not a social call: nobody is dropped
      // into it with a live microphone.
      'startWithAudioMuted': !asModerator,
      'startWithVideoMuted': !asModerator,
      // Both spellings. Jitsi moved this from `prejoinPageEnabled` to
      // `prejoinConfig.enabled` and deployments run different versions;
      // an unknown key is ignored, a missing one puts a "join meeting"
      // screen in front of thirty children who have already pressed
      // join once.
      'prejoinPageEnabled': false,
      'prejoinConfig': {'enabled': false},
      'disableDeepLinking': true,
      // A lobby is a second waiting room in front of the register, and
      // the register already decided who is in this class.
      'lobby': {'enableChat': false, 'autoKnock': true},
      // The name comes from the LogicClass account and is not the
      // child's to edit: the register is the point of the lesson.
      'requireDisplayName': false,
      'readOnlyName': true,
      // Nothing that offers a Jitsi identity to manage.
      'disableProfile': true,
      'hideEmailInSettings': true,
    },
    'interfaceConfigOverwrite': {
      // No sign-in, sign-out or profile anywhere in the interface. On a
      // deployment that needs no authentication these do nothing; on
      // one reached before the token arrives they are the difference
      // between a child pressing "log in" and a child waiting. A pupil
      // account has no Jitsi identity to manage and should not be shown
      // a door to one.
      'AUTHENTICATION_ENABLE': false,
      'SETTINGS_SECTIONS': <String>['devices'],
      // No invite button. Who is in a lesson is decided by who is on the
      // register, and a share-link button in a child's hand is the one
      // control that would undo that.
      'TOOLBAR_BUTTONS': <String>[
        'microphone', 'camera', 'desktop', 'fullscreen', 'hangup',
        'chat', 'raisehand', 'tileview', 'settings',
        // Deliberately absent, beyond the invite button: 'profile'
        // (a Jitsi identity nobody here has), 'recording' and
        // 'livestreaming' (refused in the token as well).
      ],
      'SHOW_JITSI_WATERMARK': false,
      'MOBILE_APP_PROMO': false,
    },
  };

  // Jitsi's own constructor is third-party code running against a live
  // DOM, and every way it can fail ends in front of a class. Whatever it
  // throws, the screen gets a null and offers the tab instead.
  try {
    final instance = api.callAsConstructor<JSObject>(
      meetingDomain.toJS,
      options.jsify(),
    );
    return JitsiCall._(instance);
  } catch (error) {
    debugPrint('The Jitsi call could not be constructed: $error');
    return null;
  }
}

/// A running meeting.
extension type JitsiCall._(JSObject _api) implements JSObject {
  external void dispose();
  external void executeCommand(String command);

  /// Jitsi's own events. The only way to learn whether the conference
  /// actually came up: the iframe is another origin, so nothing about
  /// what happened inside it is readable from here except what the API
  /// chooses to tell us.
  external void addListener(String event, JSFunction listener);
}
