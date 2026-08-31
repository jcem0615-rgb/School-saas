# Going live

The app ships in demo mode: an in-memory store, twelve demo accounts, no
network. That stays exactly as it is — everything below is the *other*
mode, and turning it on takes nothing away.

Real mode is `DEMO_MODE=false`. It needs a Firebase project, which only
you can create, so this is the list of steps that are yours.

## 1. Create the Firebase project

console.firebase.google.com → **Create a project**. Analytics is
optional and nothing here uses it.

Then, in order:

**Upgrade to Blaze.** Project settings → Usage and billing → Modify
plan. Cloud Functions will not deploy on the free Spark plan, and this
app is thirty-seven callables and triggers. Blaze is pay-as-you-go with
the free tier still applied underneath — a school of a thousand students
costs a few dollars a month — but it wants a card before it will run a
single function. Set a budget alert while you are on that page.

> **If you have no card yet**, everything else on this page can still be
> done on the free Spark plan: create the project, enable Email/Password,
> create Firestore in the right region, turn on Storage, register the
> web app. Only `firebase deploy --only functions` needs Blaze.
>
> What you cannot do is go live in the meantime. Signing in, creating any
> account, recording a payment, running the rollover and enrolling an
> applicant are all callables, so an app pointed at a project with no
> functions is a login screen and nothing behind it. **Leave `DEMO_MODE`
> unset until the functions are deployed** — the demo is a complete
> school with twelve accounts and needs no billing at all, which is the
> right thing to be showing anybody until then.

**Authentication** → Get started → **Email/Password**. Enable it.
Nothing else: no Google sign-in, no anonymous. The app provisions
accounts server-side (`provisionUser`), so a provider that lets somebody
sign themselves up is a hole in the role model rather than a
convenience.

**Cloud Firestore** → Create database → **Native mode**, location
**asia-southeast1 (Singapore)**.

> The location is permanent. It cannot be changed afterwards without
> creating a new project and moving the data, and every one of this
> app's functions is deployed to `asia-southeast1` — a Philippine user
> base reaching a database in Iowa pays for it on every screen. This is
> the one choice on this page you cannot take back.

Start in **production mode** if it offers the choice. The real rules go
up in step 2 and replace whatever it starts with; what you must not do
is leave it in test mode, which is world-readable and expires after
thirty days into world-*nothing*. The preflight in
[Module 21](21-system-check.md) checks for exactly this.

**Cloud Storage** → Get started, same region.

**Register a Web app.** Project settings → General → Your apps → Web
(`</>`). Give it a nickname; skip Firebase Hosting, the app is on
Vercel. The `firebaseConfig` block it shows you is what step 5 needs —
`apiKey`, `appId`, `projectId`, `messagingSenderId`, `storageBucket`,
`authDomain`. That panel is always there; you are not losing anything by
closing it.

Register Android and iOS apps too if you intend to ship those, and keep
`google-services.json` / `GoogleService-Info.plist`.

## 2. Deploy the rules and functions

```sh
firebase deploy --only firestore:rules,firestore:indexes,storage:rules
cd functions && npm install && npm run build
firebase deploy --only functions
```

The indexes are not optional and are easy to skip, because a missing one
does not fail at deploy time and does not fail in testing on a small
collection: Firestore serves a short collection without one and starts
refusing as the school grows. The preflight probes for each of them.

The functions are deployed to `asia-southeast1`. That is set per-function
in the source; changing it means editing every `onCall` region.

## 3. Set the owner email, before anything else

`bootstrapOwner` reads `OWNER_EMAIL` from its own environment. Nothing the
client sends is trusted — this is the only thing that decides who may
claim the owner role.

```sh
firebase functions:secrets:set OWNER_EMAIL
# enter your address when prompted, then redeploy functions
```

## 4. Claim the owner role, once

1. Sign up through Firebase Auth with that exact email.
2. **Verify the address.** `bootstrapOwner` refuses an unverified one, so
   that nobody can claim the configured address on a provider that hands
   out unverified sign-ups.
3. Call the `bootstrapOwner` callable while signed in as that account.
4. Sign out and back in. The role lives in a custom claim, and your
   client is still holding the token from before it was granted.

The function then closes the door behind you: it writes
`platform_config/owner` and refuses everyone afterwards, including your
own email. There is no second owner and no way to re-run it. If you ever
genuinely need to move the role to a different account, delete that
document with the Admin SDK — deliberately, not from the app; the rules
deny every client write to it.

## 5. Build with the project settings

The Firebase values arrive as `--dart-define` rather than a generated
`firebase_options.dart`, so the repository still compiles for anyone who
only wants the demo. See `app/lib/firebase_config.dart`.

### The web app, which deploys itself

Set them as **repository variables**, and the next push to `main` is the
real thing. Settings → Secrets and variables → Actions → **Variables**:

| Variable | From |
| --- | --- |
| `DEMO_MODE` | `false` |
| `FIREBASE_API_KEY` | the `firebaseConfig` block from step 1 |
| `FIREBASE_APP_ID` | same |
| `FIREBASE_PROJECT_ID` | same |
| `FIREBASE_MESSAGING_SENDER_ID` | same |
| `FIREBASE_STORAGE_BUCKET` | same, optional |
| `FIREBASE_AUTH_DOMAIN` | same, optional — web sign-in wants it |

Variables and not secrets. These are client identifiers: they ship
inside every build, Firebase expects them to be public, and what
protects the data is `firestore.rules` and the callables' own checks.
Keeping them readable means anybody debugging a deploy can see which
project a site was built against, which is the first thing worth knowing
when one comes up pointed at the wrong one.

Set `DEMO_MODE=false` without the four required values and the build
stops, naming what is missing, and the previous deployment keeps
serving. That is the intended failure — better than a live site that
loads and then dies at sign-in.

**Do steps 2 to 4 first.** A site pointed at a project with no rules and
no functions deployed signs in and then denies every read, which looks
far more broken than the demo it replaced.

### Android and iOS, which are built by hand

```sh
flutter build apk --release \
  --dart-define=DEMO_MODE=false \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=...   # web only
```

Missing values fail at startup naming the ones that are absent, rather
than with the SDK's own "no Firebase app" message, which says nothing
about which.

Android additionally needs `google-services.json` in `app/android/app/`
and the Google Services Gradle plugin applied if you want push
notifications; iOS needs `GoogleService-Info.plist`.

## Who can create whom

Enforced in `functions/src/callable/users/provisionUser.ts`, server-side.
The client never decides this.

| Signed in as | Can create |
| --- | --- |
| Owner | Director, Admin |
| Director | Admin, Principal, Registrar, Faculty, Staff, Guidance |
| Admin | Principal, Registrar, Faculty, Staff, Guidance |
| Registrar | Student, Parent |

**Owner appears in no row.** `provisionUser` refuses the owner role
outright, so the only route to it is step 4 above — which runs once.

The Owner can create a Director *and* an Admin so a new school can be
stood up without signing in as its Director first just to make the Admin.

## Adding a school

There is no sign-up. Schools exist because you add them: Owner portal →
School Management → **Add School**.

A school is three documents — the platform record, its subscription, and
the tenant-side profile — written in one transaction. Half a school is
invisible in your list and unusable by its Director, so it is all or
nothing. The id is derived from the name and is **permanent**: every
account and every record in that school is scoped to it, and Firestore
document ids cannot be renamed.

Then provision its Director, who staffs the rest.

## How the web app reaches Vercel

Two arrangements are possible, and only one should be active at a time.

**The Git integration** (Vercel project -> Settings -> Git, connected to
this repository, production branch `main`). Vercel builds from source on
every push using the `installCommand` and `buildCommand` in
`vercel.json`, and gives a preview deployment per branch.

It is connected, and it does not work. Builds run and fail inside
Vercel's build container, and a failed build leaves the previous
deployment serving -- so `logicclass.vercel.app` served a commit from 26
August while `main` ran twenty-nine commits ahead, with no outward sign
that anything was wrong. This was misdiagnosed once as "the project has
no Git integration", because from outside, a push that never arrives and
a push that arrives and dies in the build look the same. Check the
project's Deployments tab before believing either story.

The likely culprit is `scripts/vercel-install.sh`, which clones the
whole Flutter SDK into the build container and then has it download a
Dart SDK on first run. That is a lot of disk and minutes for a Hobby
build image. Unconfirmed: the build log says which, and it is one click
from the failed deployment.

**`.github/workflows/deploy-web.yml`**, which is the arrangement now in
use. It builds the app in CI with a cached Flutter action -- no SDK
clone, nothing for a build container to run out of -- and pushes the
finished files to the project with the Vercel CLI. Turn the Git
integration off (Settings -> Git -> Disconnect) when you enable this,
or both will deploy and Vercel will keep sending failed-build mail for
deploys nobody is waiting on.

It needs **one** repository secret:

| Secret | Where it comes from |
|---|---|
| `VERCEL_TOKEN` | vercel.com/account/tokens, scoped to the owning account |

The org and project ids are written into the workflow's `env` block
instead. They are not secrets -- Vercel documents them as identifiers,
and holding one gets you nothing without the token -- and a value nobody
can see is a value nobody can check when a deploy lands somewhere
unexpected.

Worth knowing where the org id comes from, because the obvious place
does not have it: a Hobby account's project page shows a Project ID and
no Team ID, since there is no team. The id exists all the same and the
API returns it; it is in the workflow.

The job checks for the token before doing anything, rather than letting
the CLI fail three steps later. A run that spends five minutes building
before saying "no token" is five minutes nobody gets back.

**If somebody fixes the Vercel-side build, delete the workflow.** Both
would deploy every push, and the site would rebuild twice for no reason.
`vercel.json` and `scripts/vercel-install.sh` are kept in the repository
for that -- they are the way back, not dead files.

### If a deploy fails in seconds with no log

Check the job, not the workflow. A job that ran and failed has a
`runner_name` and a list of steps; a job that failed because the account
has no Actions minutes left has `runner_id: 0`, no runner name, and no
steps at all -- it never reached a machine. The two look the same in the
Actions list, and only the second is a billing problem.

This repository is public, so Actions minutes are free and this failure
should not recur. It is written down because it did happen, and because
a repository that goes private again brings it straight back. Where the
minutes would go:

| Job | Runner | Billed at |
|---|---|---|
| Deploy web | ubuntu-latest | 1x |
| Installable builds / apk | ubuntu-latest | 1x |
| Installable builds / windows | windows-latest | 2x |
| Installable builds / ios | macos-latest | 10x |

Only the first two run automatically. Windows and iOS are
`workflow_dispatch` only -- now for time rather than money, since a
macOS runner adds the better part of an hour to a merge and answers a
question that does not change between commits.

Usage, if the repository is ever private again, is at
**github.com/settings/billing**.

### Why it deploys built files rather than sources

Nothing to install or compile on Vercel's side, so a build that works in
CI is the build that ships. It does mean the deployed directory needs
its own `vercel.json` -- the repository's describes how to build from
source and is the wrong shape for a directory of finished files -- so
the workflow writes a two-line one carrying the same rewrite, for the
same reason. See below.

## The web deploy, and the two ways it goes blank

A Flutter web page is one async script tag. If that script does not run,
the result is a white page with nothing on it and nothing in the console
a visitor would think to look at — no error, no partial render, no clue.
Two things in a Vercel deploy can cause that, and both are guarded now.

**The rewrite.** `vercel.json` used to send every path to `/index.html`.
That is meant to be filesystem-first, and normally is — but if
`outputDirectory` ever fails to resolve, a catch-all serves index.html
for `main.dart.js` too. The browser gets HTML where it expected
JavaScript, nothing runs, and the page is blank. The rewrite now excludes
anything containing a dot, so only extensionless route paths fall back.

**The service worker.** Flutter's `flutter_service_worker.js` cached the
whole app and served it ahead of the network. A visitor who loaded an
earlier build keeps being served that build's asset list, and once one
entry no longer matches, the app never boots. A hard reload fixes it;
nobody knows to try one. The build passes `--pwa-strategy=none` so no new
visitor gets one, and `web/index.html` carries a kill switch that
unregisters any worker a previous deploy left behind, clears its caches
and reloads once. Flutter's own generated bootstrap already calls this
worker deprecated. Offline caching is worth little to a site opened once
from a link, and worth a great deal less than a page that loads.

The kill switch is scoped to Flutter's worker by script URL:
`firebase-messaging-sw.js` is registered by the messaging SDK for web
push and has to survive. It is guarded by a `sessionStorage` flag so it
runs once, and every call is wrapped — a blocked service worker API is
not a reason to stop the app loading.

Verified in Chromium against a build from `scripts/vercel-build.sh`: a
clean visitor renders the login with no worker registered; a visitor
carrying a planted worker has it evicted, reloads once, and renders. The
document-load count holds steady over 25 seconds, so the eviction cannot
loop.
