import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/install/install_prompt_factory.dart';

/// The install offer on a non-web build, and the browser-side conditions
/// the web build depends on.
void main() {
  group('a non-web build', () {
    test('has nothing to install', () {
      // The point of the conditional export: a phone build never compiles
      // `package:web` and never offers to install the app it is already
      // running inside. The suite runs on the VM, so it takes the stub.
      expect(createInstallPrompt().offer, InstallOffer.none);
    });

    test('refuses rather than throwing when asked anyway', () {
      // The button never calls this when the offer is none, but a stub
      // that threw would turn a mis-wired screen into a crash.
      expect(createInstallPrompt().show(), completion(isFalse));
    });

    test('hands back a no-op unsubscribe, which dispose calls', () {
      // The widget calls this unconditionally in dispose. A stub
      // returning null, or nothing, would crash every non-web build the
      // moment the sign-in screen went away.
      final stop = createInstallPrompt().listen(() {});
      expect(stop, isNotNull);
      expect(stop, returnsNormally);
    });
  });

  /// Why this reads the shipped web files.
  ///
  /// Chromium fires `beforeinstallprompt` -- the event the whole install
  /// button is built on -- only for a page with a registered service
  /// worker whose fetch handler can answer offline. This build passes
  /// `--pwa-strategy=none` to keep Flutter's asset-caching worker out
  /// (it serves a stale asset list after a redeploy and the page goes
  /// white), and for a while that left *no* worker, so the button could
  /// never appear on Chrome, Edge or Android. It was in the code and
  /// unreachable.
  ///
  /// Nothing in Dart can assert that. These read the files that decide
  /// it, so removing the worker again fails here rather than silently
  /// switching the button off on every Chromium browser.
  group('the browser conditions the button depends on', () {
    String read(String relative) {
      final file = File('web/$relative');
      expect(file.existsSync(), isTrue, reason: 'web/$relative is missing');
      return file.readAsStringSync();
    }

    test('index.html registers a service worker of our own', () {
      expect(read('index.html'), contains("serviceWorker.register('app_sw.js')"));
    });

    test('and that worker has a fetch handler, which is the criterion', () {
      expect(read('app_sw.js'), contains("addEventListener('fetch'"));
    });

    test('the worker caches an offline page and nothing from the build', () {
      final worker = read('app_sw.js');
      expect(worker, contains('offline.html'));
      // The cache holds one page. Naming a build asset here would be the
      // white-screen-after-redeploy failure the build flag exists to
      // prevent, arriving by another door.
      for (final asset in ['main.dart.js', 'flutter_bootstrap.js', 'canvaskit', 'index.html']) {
        expect(worker.contains('$asset"'), isFalse, reason: 'must not cache $asset');
        expect(worker.contains("'$asset'"), isFalse, reason: 'must not cache $asset');
      }
      // And the offline page stands alone: anything it referenced would
      // have to be cached too, which is how an offline page becomes a
      // stale copy of the app.
      final offline = read('offline.html');
      expect(offline, isNot(contains('<script src')));
      expect(offline, isNot(contains('<link rel="stylesheet"')));
      expect(offline, isNot(contains('<img')));
    });

    test('the eviction sweep leaves our worker and its cache alone', () {
      // index.html unregisters the *Flutter* worker a returning visitor
      // may still carry. Scoped by script URL, and its cache sweep skips
      // ours -- an eviction that took both would switch the install
      // button off again on every visit that triggered it.
      final html = read('index.html');
      expect(html, contains('flutter_service_worker.js'));
      expect(html, contains("k.indexOf('logicclass-offline-') !== 0"));
    });

    test('the manifest still meets the rest of the bar', () {
      // Name, 192 and 512 icons, a start url and a standalone display.
      // Chromium checks all of them; any one missing is the same silent
      // "no button" as a missing worker.
      final manifest = read('manifest.json');
      for (final required in [
        '"name"',
        '"start_url"',
        '"display": "standalone"',
        '192x192',
        '512x512',
      ]) {
        expect(manifest, contains(required), reason: 'manifest needs $required');
      }
    });

    test('the page tells Dart when the offer arrives', () {
      // `beforeinstallprompt` lands after first paint and the sign-in
      // screen is static. Without this the button read the offer once,
      // got "none", and nothing ever rebuilt it to ask again.
      expect(read('index.html'), contains('onChange: function (callback)'));
    });
  });
}
