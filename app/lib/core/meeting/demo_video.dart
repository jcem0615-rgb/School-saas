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
            Uri.parse(endpoint),
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
