// The smallest service worker that makes this site installable.
//
// Chromium will not fire `beforeinstallprompt` -- the event the whole
// install button depends on -- unless the page has a registered service
// worker with a fetch handler that can answer when the network is gone.
// Without one, the button in the Dart code can never render on Chrome,
// Edge or Android, which is exactly where it did not.
//
// This is NOT Flutter's `flutter_service_worker.js`, and the difference
// is the entire point. That one precaches the build's whole asset
// manifest and serves it ahead of the network, which is the classic way
// a redeploying site goes white: a visitor holding an older asset list
// keeps being served it, one entry stops matching, and main.dart.js
// never runs. `--pwa-strategy=none` in scripts/vercel-build.sh exists to
// stop that, and nothing here undoes it.
//
// So the rules this worker holds to:
//
//   * It never caches a build asset. Not main.dart.js, not canvaskit,
//     not an icon. There is nothing here that can go stale against a
//     new deploy, because there is nothing here from the build.
//   * It does not touch non-navigation requests at all -- no
//     respondWith, so the browser fetches them exactly as it would with
//     no worker registered. The asset path is untouched.
//   * The one thing it holds is a standalone offline page, served only
//     when a navigation fails. That is what satisfies "responds when
//     offline" and it is the whole of its cache.

// Bump to evict the previous offline page. Nothing else lives in here.
const CACHE = 'logicclass-offline-v1';
const OFFLINE_PAGE = 'offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.add(new Request(OFFLINE_PAGE, {cache: 'reload'})))
      // A failure here must not leave the worker uninstalled: no worker
      // means no install prompt, and an offline page is worth less than
      // the button this exists to switch on.
      .catch(() => undefined)
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key.startsWith('logicclass-offline-') && key !== CACHE)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  // Navigations only. Everything else falls through to the browser with
  // no respondWith at all, so assets are fetched as if no worker were
  // registered -- see the note at the top about why that matters.
  if (event.request.mode !== 'navigate') return;

  event.respondWith(
    // Network first, always. The network's answer is the current build;
    // the cache holds one page that is not part of any build.
    fetch(event.request).catch(() =>
      caches
        .match(OFFLINE_PAGE)
        .then((cached) => cached || Response.error())
    )
  );
});
