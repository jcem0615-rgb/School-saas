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

## The thing to check on a real deployment

Whether the browser fires `beforeinstallprompt` at all is its call, and
the criteria vary by version. This build passes `--pwa-strategy=none` and
actively evicts Flutter's own service worker (see the note in
`web/index.html`), leaving `firebase-messaging-sw.js`, registered by the
messaging SDK, as the only worker on the page.

Chrome's installability criteria have historically included a service
worker. **This has not been verified against a real deployed build**, and
it should be before the install button is promised to a school: open the
deployed site in Chrome on Android and on desktop and confirm the button
appears. If it does not, the fix is a minimal fetch-handling worker rather
than anything in the Dart code — the offer degrades to showing nothing,
which is correct but is not the same as working.
