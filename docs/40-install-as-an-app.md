# Module 40: Installing it as an app

## What this is

The web build is a Progressive Web App and always has been: `manifest.json`
declares a name, a standalone display mode, theme colours and maskable
icons at 192 and 512. A browser that accepts it will run LogicClass in its
own window, with its own icon, off the home screen or the taskbar — no
store, no download, no separate build.

What was missing is anything that **asks**. Browsers put the install
affordance behind a menu, so a parent told "it works like an app" had no
way to find out that it does.

## How the offer is made

`beforeinstallprompt` fires once, early — usually before Flutter has
finished booting — and is spent unless something calls `preventDefault()`
on it. So `web/index.html` catches it and holds it, and Dart asks the page
what it is holding rather than trying to listen itself. The bridge is
`window.logicClassInstall`, with `offer()` and `show()`.

| Situation | `offer()` | What shows |
|---|---|---|
| Browser has an install prompt held | `prompt` | **Install the app** |
| iOS Safari | `instructions` | *Tap Share, then Add to Home Screen* |
| Already installed, or not a browser | `none` | Nothing |

iOS gets words rather than a button because Safari never fires the event
and gives no API to trigger the sheet. A button that did nothing would be
worse than saying where the real one is.

`InstallOffer.none` is the honest default, and it is why nothing here can
produce a dead button: if a browser never offers a prompt, no button
appears.

## Where it is offered

**The sign-in screen**, because that is where somebody opening the link
lands, and installing before signing in means the session they are about
to start is the one in the installed app. And **Profile**, for somebody
who signed in first and only later wants it on their home screen.

The button removes itself after one tap, accepted or dismissed: the event
is single-use and the browser will not hand out another this visit, so
leaving it on screen would leave one that no longer works.

## Nothing of this compiles into a phone build

`install_prompt_factory.dart` is a conditional export, the same shape as
`location_probe_factory.dart`: the stub everywhere, the browser
implementation only where `dart:js_interop` exists. A phone build never
compiles `package:web`, and `InstallAppButton` renders an empty box —
an install button inside an installed app is a button that cannot do
anything.

## Why there is a service worker, and why it is not Flutter's

This is the thing the module got wrong, and it made the whole feature
unreachable on the browsers most of a school uses.

Chromium fires `beforeinstallprompt` — the event everything above is
built on — only for a page with a **registered service worker whose
fetch handler can answer when the network is gone**. This build passes
`--pwa-strategy=none` and actively evicts Flutter's own worker, for a
good reason: that worker precaches the build's whole asset manifest and
serves it ahead of the network, so a visitor holding an older asset list
keeps being served it, one entry stops matching, `main.dart.js` never
runs, and the page is white.

Both things were true, and together they meant **no worker at all** —
so the event never fired, `offer()` returned `none` on every Chromium
browser, and `InstallAppButton` rendered an empty box. The button was in
the code, on the right screen, correctly styled, and could not appear.
Only iOS Safari showed anything, because its branch is the instructions
line and does not depend on the event.

`web/app_sw.js` is the fix, and it is deliberately the smallest thing
that satisfies the browser:

* **It never caches a build asset.** Not `main.dart.js`, not canvaskit,
  not an icon. There is nothing in it that can go stale against a new
  deploy, so the failure `--pwa-strategy=none` exists to prevent cannot
  come back through this door.
* **It does not touch non-navigation requests at all** — no
  `respondWith`, so assets are fetched exactly as they would be with no
  worker registered.
* **It holds one thing**: a standalone `offline.html`, served only when a
  navigation fails. That is what satisfies "responds when offline", and
  it is the whole of its cache.

The eviction block in `index.html` is scoped to `flutter_service_worker.js`
by script URL and its cache sweep skips `logicclass-offline-*`, so it
clears the old worker without switching the new one off.

## It also has to be visible

The button took an `onDarkSurface` flag, and the sign-in screen passed
it, which pinned the foreground to white. That was written and checked
against the dark theme.

The app ships both themes and sets no `themeMode`, so the device decides.
In the dark theme the sign-in pane is a film of light over deep blue and
white reads at 15.7:1. In the light theme the pane is white glass over a
pale sky — so it was **white on white, at 1.02:1**. The button rendered,
took up space, and could not be seen; a device in light mode is the
common case, so this is what most people got.

The flag is gone. A caller cannot be asked to know what the theme already
knows: the label takes `colorScheme.primary` (6.3:1 light, 9.3:1 dark
against that pane) and the iOS instructions line takes
`onSurfaceVariant` (4.6:1 and 5.9:1). `install_contrast_test.dart`
computes those ratios from the real themes and holds both to WCAG AA,
including the light-theme white case as the regression it was.

Two bugs in the same button, and they rhyme: the first made it unable to
render, the second made it render invisibly. Both were "correct on the
machine it was written on".

## Telling Dart when the offer arrives

`beforeinstallprompt` lands well after first paint, and the sign-in
screen is static — nothing rebuilds it. So reading the offer on build was
necessary and not sufficient: the offer arrived a second after load and
nothing asked again.

`window.logicClassInstall.onChange(callback)` returns an unsubscribe
function; `InstallAppButton` subscribes in `initState` and calls it in
`dispose`. The web implementation feature-detects `onChange` before
using it, because during a rollout a browser can still be holding the
previous `index.html`.

## What was actually verified

Against the real `flutter build web --release --pwa-strategy=none`
output, served over HTTP and driven in Chromium:

| Checked | Result |
|---|---|
| `app_sw.js` registers, scope `/` | yes, active |
| What its cache holds | `offline.html`, and nothing else |
| `main.dart.js` on reload | fetched from the server, not the worker |
| Navigation with the network cut | the offline page |
| Back online | the app |
| `window.logicClassInstall` | `offer`, `show` and `onChange` all present |
| Console | no errors |

`app/test/unit/core/install_prompt_test.dart` pins the parts of that a
test can reach — the registration line, the fetch handler, the cache
holding no build asset, the eviction skipping our cache, the manifest's
own criteria, and `onChange` being there. Removing the worker again
fails there rather than silently switching the button off.

**Still worth doing by hand once on a real deployment**: open the
deployed site in Chrome on Android and on desktop and confirm the button
appears. The install prompt also depends on HTTPS and on the browser's
own engagement heuristics, and neither of those can be exercised from a
test.
