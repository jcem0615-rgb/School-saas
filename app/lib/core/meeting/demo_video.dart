import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/class_sessions/domain/entities/class_session.dart';

/// Where the demo gets a pass into a video class.
///
/// The real product mints one in `issueMeetingToken`, a Cloud Function
/// that checks the register first. Cloud Functions need Firebase's Blaze
/// plan and a card, and the demo has neither -- so the demo would show
/// every part of holding a lesson except the lesson, which is the part
/// people want to see.
///
/// The site is already on Vercel, so the pass comes from one serverless
/// file there instead: `vercel/api/livekit-token.js`. Same origin, so
/// there is no CORS to arrange and nothing to configure in the app. The
/// API secret stays in Vercel's environment and never reaches a browser.
///
/// **This is not a security model, and is not pretending to be one.**
/// The endpoint checks that the room looks like one this app generates
/// and nothing else -- there is no register behind the demo to check a
/// person against. What keeps a stranger out of a demonstration is the
/// same thing that keeps them out of a real lesson: the room name is
/// 120 random bits and is never shown to anybody who was not given it.
class DemoVideo {
  /// Same-origin, so this works wherever the demo is deployed and needs
  /// no build-time configuration at all.
  static const endpoint = '/api/livekit-token';

  /// The endpoint, resolved against wherever the app is being served.
  ///
  /// Absolute rather than relative. A browser resolves `/api/...`
  /// against the page on its own, so the relative form usually works --
  /// but "usually" is not worth the round trip it costs to find out,
  /// and an HTTP client is entitled to want a scheme.
  static Uri get uri => Uri.base.resolve(endpoint);

  /// What the deployment holds, in one line, or null if it will not say.
  ///
  /// The endpoint answers a GET with the shape of its three LiveKit
  /// values -- lengths, prefixes, punctuation -- and a list of the
  /// mistakes that shape can prove. It prints no value, which is what
  /// makes it safe to put on a screen.
  ///
  /// It is fetched only after a join has already failed, and only on a
  /// demo, where the person reading the failure is the person who can
  /// fix it. Asking whoever is configuring this to go and open a URL
  /// cost two rounds already; the card they are looking at can say it.
  static Future<String?> configurationSummary({http.Client? client}) async {
    final http.Client sender = client ?? http.Client();
    try {
      // Longer than the pass request, on purpose: the endpoint asks
      // LiveKit about its own keys before it answers this, and a
      // timeout here would throw away the one answer worth waiting for.
      // The card is already on screen; only this line is late.
      final reply = await sender.get(uri).timeout(const Duration(seconds: 15));
      if (reply.statusCode != 200) return null;

      final body = jsonDecode(reply.body);
      if (body is! Map) return null;

      // The endpoint writes the line itself when it can. That is not
      // deference -- it is the one file here that can be improved and
      // deployed without rebuilding anything, so a better sentence is
      // minutes away rather than a release away.
      final summary = body['summary'];
      if (summary is String && summary.trim().isNotEmpty) {
        return summary.trim();
      }

      final problems = body['problems'];
      if (problems is List && problems.isNotEmpty) {
        return problems.whereType<String>().join('\n\n');
      }

      // Nothing visibly wrong, which is itself the finding: the values
      // are well-formed and LiveKit still refuses them, so they are not
      // a matching set. The shapes go on the line anyway -- they are
      // the difference between "nothing is wrong" and "here is what it
      // holds", and the second can be read off a photograph.
      final values = body['values'];
      if (values is! Map) return null;
      String shapeOf(String name, String extra) {
        final value = values[name];
        if (value is! Map) return '$name ?';
        return '$name ${value['characters']} $extra';
      }

      final url = values['LIVEKIT_URL'];
      return 'All three are the right shape -- '
          '${shapeOf('LIVEKIT_URL', url is Map ? '${url['scheme']}' : '')}, '
          '${shapeOf('LIVEKIT_API_KEY', 'chars')}, '
          '${shapeOf('LIVEKIT_API_SECRET', 'chars')} -- '
          'so they are not a matching set. Copy all three again from '
          "one LiveKit project's Settings -> Keys page.";
    } catch (error) {
      debugPrint('No configuration summary: $error');
      return null;
    } finally {
      if (client == null) sender.close();
    }
  }

  /// Asks for a pass, and returns [MeetingAdmission.none] if there is
  /// none to be had.
  ///
  /// Absent is the ordinary case: a demo running anywhere that has not
  /// set the three LiveKit values answers 404, and the screen then says
  /// live video is not part of the demo. That is a state to be reported,
  /// not an error to be thrown in front of somebody.
  static Future<MeetingAdmission> passFor({
    required String room,
    required String identity,
    required String name,
    http.Client? client,
  }) async {
    final http.Client sender = client ?? http.Client();
    try {
      final reply = await sender
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'room': room, 'identity': identity, 'name': name}),
          )
          .timeout(const Duration(seconds: 10));

      if (reply.statusCode != 200) return MeetingAdmission.none;

      final body = jsonDecode(reply.body);
      if (body is! Map) return MeetingAdmission.none;
      final url = body['url'];
      final token = body['token'];
      if (url is! String || token is! String || url.isEmpty || token.isEmpty) {
        return MeetingAdmission.none;
      }
      return MeetingAdmission(provider: 'livekit', url: url, token: token);
    } catch (error) {
      // No endpoint at all is the common case -- the demo run from a
      // laptop, or deployed somewhere without one. The lesson screen
      // says live video is not set up, which is true and is better than
      // an exception in front of whoever is being shown the product.
      debugPrint('No demo video pass: $error');
      return MeetingAdmission.none;
    } finally {
      if (client == null) sender.close();
    }
  }
}
