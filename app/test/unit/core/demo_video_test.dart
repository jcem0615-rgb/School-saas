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

  // `invalid token` is the one failure the endpoint cannot see while it
  // is minting: all three values are present, so it signs, and only
  // LiveKit knows they are wrong. A GET on it describes what it holds,
  // and the failure card puts that on the screen rather than sending
  // whoever is configuring this off to open a URL.
  group('asking what the deployment holds', () {
    test('repeats the problems it was given, and nothing else', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response(
          jsonEncode({
            'configured': true,
            'problems': [
              'LIVEKIT_API_KEY and LIVEKIT_API_SECRET look swapped.',
              'LIVEKIT_URL does not begin with wss://.',
            ],
            'values': {},
          }),
          200,
        );
      });

      final summary = await withClient(
        client,
        (c) => DemoVideo.configurationSummary(client: c),
      );

      expect(summary, contains('look swapped'));
      expect(summary, contains('does not begin with wss'));
    });

    test('says the shapes are right when there is nothing to report',
        () async {
      // Not silence. Well-formed values that LiveKit still refuses are
      // a finding -- they came from two different projects -- and the
      // numbers are what make that readable off a photograph of a
      // screen.
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'configured': true,
              'problems': <String>[],
              'values': {
                'LIVEKIT_URL': {'characters': 38, 'scheme': 'wss'},
                'LIVEKIT_API_KEY': {'characters': 13},
                'LIVEKIT_API_SECRET': {'characters': 43},
              },
            }),
            200,
          ));

      final summary = await withClient(
        client,
        (c) => DemoVideo.configurationSummary(client: c),
      );

      expect(summary, contains('13'));
      expect(summary, contains('43'));
      expect(summary, contains('wss'));
      expect(summary, contains('not a matching set'));
    });

    test('has nothing to say when the endpoint will not answer', () async {
      for (final reply in [
        http.Response('{"error":"not configured"}', 404),
        http.Response('not json at all', 200),
        http.Response('[]', 200),
      ]) {
        final client = MockClient((request) async => reply);
        final summary = await withClient(
          client,
          (c) => DemoVideo.configurationSummary(client: c),
        );
        expect(summary, isNull, reason: 'for ${reply.statusCode} ${reply.body}');
      }
    });

    test('and none when it cannot be reached at all', () async {
      final client = MockClient((request) async => throw const SocketishFailure());

      final summary = await withClient(
        client,
        (c) => DemoVideo.configurationSummary(client: c),
      );

      expect(summary, isNull);
    });
  });
}

class SocketishFailure implements Exception {
  const SocketishFailure();
}
