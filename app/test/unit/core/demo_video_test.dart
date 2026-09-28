import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logicclass/core/meeting/demo_video.dart';

/// Where the demo gets a pass into a video class.
///
/// Tested hard on the refusals rather than the happy path, because the
/// common case is that there is no endpoint at all -- a demo run from a
/// laptop, or deployed without the LiveKit values -- and every one of
/// those has to come back as "no video here" rather than as an
/// exception in front of somebody being shown the product.
void main() {
  const room = 'lc-abcdefghijklmnopqrst';

  Future<T> withClient<T>(
    MockClient client,
    Future<T> Function(http.Client) body,
  ) async {
    try {
      return await body(client);
    } finally {
      client.close();
    }
  }

  group('asking for a pass', () {
    test('carries the room, the identity and the name', () async {
      // The identity is the signed-in demo account, so a teacher and a
      // student in two browsers are two people in the room rather than
      // one identity arriving twice and knocking itself out.
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'url': 'wss://x.livekit.cloud', 'token': 'a.b.c'}),
          200,
        );
      });

      final pass = await withClient(
        client,
        (c) => DemoVideo.passFor(
            room: room, identity: 'u_faculty', name: 'Ms Santos', client: c),
      );

      expect(sent['room'], room);
      expect(sent['identity'], 'u_faculty');
      expect(sent['name'], 'Ms Santos');
      expect(pass.provider, 'livekit');
      expect(pass.url, 'wss://x.livekit.cloud');
      expect(pass.token, 'a.b.c');
    });

    test('no endpoint deployed is "no video here", not a failure', () async {
      // A demo without the LiveKit values answers 404. That is the
      // ordinary state and the screen says live video is not switched
      // on, which is true.
      final pass = await withClient(
        MockClient((_) async => http.Response('{"error":"not configured"}', 404)),
        (c) => DemoVideo.passFor(
            room: room, identity: 'u', name: 'n', client: c),
      );
      expect(pass.provider, 'none');
      expect(pass.token, isNull);
    });

    test('a refused room is the same answer', () async {
      final pass = await withClient(
        MockClient((_) async => http.Response('{"error":"nope"}', 400)),
        (c) => DemoVideo.passFor(
            room: room, identity: 'u', name: 'n', client: c),
      );
      expect(pass.provider, 'none');
    });

    test('a network that is not there does not throw at a class', () async {
      final pass = await withClient(
        MockClient((_) async => throw const SocketishFailure()),
        (c) => DemoVideo.passFor(
            room: room, identity: 'u', name: 'n', client: c),
      );
      expect(pass.provider, 'none');
    });

    test('nonsense in the reply is refused rather than half-used', () async {
      // A 200 with no token would otherwise become a "livekit" pass
      // carrying nothing, and the classroom would try to join with it.
      for (final body in const [
        '{"url":"wss://x"}',
        '{"token":"a.b.c"}',
        '{"url":"","token":"a.b.c"}',
        '[]',
        'not json at all',
      ]) {
        final pass = await withClient(
          MockClient((_) async => http.Response(body, 200)),
          (c) => DemoVideo.passFor(
              room: room, identity: 'u', name: 'n', client: c),
        );
        expect(pass.provider, 'none', reason: 'accepted $body');
      }
    });

    test('is same-origin, so a demo needs no configuration to reach it',
        () async {
      expect(DemoVideo.endpoint, startsWith('/'));
      expect(DemoVideo.endpoint, isNot(contains('://')));
    });

    test('is asked for as an absolute address, not a bare path', () async {
      // A browser resolves a relative path against the page on its own,
      // and an HTTP client is entitled to want a scheme. Resolving it
      // here costs nothing and removes a thing that could go wrong in
      // front of a class.
      expect(DemoVideo.uri.hasScheme, isTrue);
      expect(DemoVideo.uri.path, DemoVideo.endpoint);
    });
  });
}

class SocketishFailure implements Exception {
  const SocketishFailure();
}
