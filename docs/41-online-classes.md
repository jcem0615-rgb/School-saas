# Module 41: Holding the class online

## What this is

A lesson that happens in the app. The teacher takes today's class
online from the register; every student on that register gets a way in;
the video runs inside LogicClass rather than in somebody else's product.

It is Jitsi, and that is not an arbitrary choice — see below.

## Why not Zoom or Google Meet

Because neither can be *inside* the app, and the request was for inside.

Both send `X-Frame-Options` / `frame-ancestors` headers that refuse to
be framed at all. A school system that says "join class" and opens
Zoom is linking out, which is what Google Classroom and Canvas do and is
a perfectly good product — it is just not the thing asked for. Zoom has
a Web SDK that *can* be embedded, but it needs a Zoom developer app,
account credentials and a server-side signature per meeting, which is a
subscription and an integration rather than a feature.

Jitsi is designed to be embedded: a page loads `external_api.js` from
the deployment and hands it a parent element. No account, no key.

## The room name is the whole of the security

A Jitsi room is created by the first person to open its URL. There is no
password step between knowing the name and being in a lesson with forty
children, so the name is the secret and `shared/meeting/room.ts` exists
to keep it one.

**It carries nothing about the class.** The obvious name is
`logicclass-school_a-grade10-rizal-math-2026-09-23`, and it is wrong
twice. It is *guessable* — built from three things everyone at a school
knows, so an expelled student or a stranger reading a timetable on a
noticeboard is one URL away from a live class. And it is *readable* — it
sits in the address bar of every participant and in whatever they paste
into a chat, disclosing the school, the section and the subject to
anyone who ever sees the link.

So it is 15 random bytes, lower-case alphanumeric, prefixed `lc-`, and
says nothing. What class it belongs to is recorded on the session
document, behind the rules, where that belongs.

**It is per session, never reused.** A room kept across every Monday is
a door last term's leaver still has a key to, and nothing about their
leaving would have closed it.

**It is not written to the audit log.** The log is read school-wide;
copying the room there would hand every account in the office a way into
any lesson. The log records that a class went online and for how many
students, and not where.

## How a student gets the room without a rule being widened

`classSessions` is staff-only in `firestore.rules`, deliberately: the
session document is the whole register, and a student has no business
reading how the rest of the class came out. But the student is exactly
who needs the room.

So the room is stamped onto **every student's own line in the register**
— `subjectAttendance/{sessionId}_{studentId}` — which they and their
linked parent can already read and nobody else's child can. Nothing
about holding a class online required widening a single rule, which is
the part of this that would have been easy to get wrong.

## Shutting the door

Three ways a room stops existing, and all three clear it from the
session **and** from every mark:

* The teacher brings the class back in person.
* The teacher takes it online again — a fresh room, so a link copied a
  minute ago is already dead.
* **Time Out.** Without this the lesson ends, the teacher leaves, and a
  class of children is in an unsupervised video call reachable from a
  register that says the class is over. `closeClassSession` clears it,
  including for students marked absent — a child who was not in the
  lesson must not be left holding the way into it either.

## How a teacher gets to it

**Faculty Dashboard → Online Class.** Its own tile, beside Class
Attendance.

It was reachable only through Class Attendance → the day's list → Time
In → the register → Take online. That is four steps under a tile called
"Class Attendance", which is not a path anybody guesses at on the
morning classes are suspended — and a feature nobody can find is a
feature that is not there.

The tile opens the same screen Class Attendance does, because the day's
classes are what you need either way. What changed is that every class
on it now carries **Start online class** next to Time in.

That button is one tap rather than three. A lesson cannot be held online
without a register — the room is stamped onto each student's mark, which
is how they reach it — so it opens the session if it is not open, takes
it online if it is not online, and goes in. A teacher who has just been
told classes are suspended should not have to know that order. If the
class is already online it says **Join online class** and goes straight
in, rather than opening a second room and stranding whoever is waiting
in the first.

It is not offered on a class that has finished: the server refuses to
open a room on a closed register, and a button whose only outcome is an
error message is worse than no button.

A student needs no tile. The banner on their dashboard appears when
their teacher starts the class and goes away when it ends, which is the
only time there is anything to join.

## The teacher decides, not the timetable

Per session, by the teacher, because the reasons are same-day ones: a
typhoon, a suspension of classes, a teacher isolating. A school that has
to edit its timetable at 6am to hold a lesson will not hold the lesson.

The control is on the register, next to the roll, because that is the
screen the teacher already has open at the start of a class.

## What runs where

| Platform | What happens |
|---|---|
| Browser (the deployed PWA) | The meeting renders in the screen, in a platform view Jitsi attaches its iframe to. |
| Android, iOS | `jitsi_meet_flutter_sdk` puts its own full-screen conference in front of the person, in this app's process. No browser, no second app. |
| Windows, macOS, Linux | No SDK exists, so the room goes to the operating system — the Jitsi app if installed, the browser if not. The screen says so. |

The native SDK is not a Flutter widget: it draws over the classroom
screen rather than inside it. So `OnlineClassScreen` stays mounted
underneath, and what somebody sees when they leave the call is that
screen offering to rejoin — which is what you want when a child leaves
by accident with forty minutes of the lesson left.

The seam is `MeetingLauncher` plus the `meeting_view_factory`
conditional export, the same shape as `install_prompt_factory` and
`location_probe_factory`. `MeetingSupport` names the three cases so a
screen never has to guess which it is in.

### What the SDK cost

* **Android `minSdk` went 23 → 24.** The Jitsi Android SDK does not
  support 23. That drops Android 6.0 Marshmallow, which for a school
  with very old handsets is a real cost — written down in
  `build.gradle.kts` rather than quietly bumped.
* **Three permissions**: `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, and
  `BLUETOOTH_CONNECT`. The last is the one that gets forgotten: without
  it Android 12+ will not let the SDK see a paired headset, and a
  student wearing earphones hears the lesson through the loudspeaker in
  a room with other people.
* **iOS** needs `NSMicrophoneUsageDescription`, which is now in
  `Info.plist`. It also needs `platform :ios, '15.1'` or later in the
  Podfile — **there is no Podfile in the repo yet**, because iOS has
  never been built here; whoever runs the first `pod install` on a Mac
  has to set it.

**Neither mobile build has been compiled.** There is no Android SDK and
no Xcode in the environment this was written in, so the Gradle and
CocoaPods sides of this are unverified. The web build was rebuilt and
booted clean with the plugin in the pubspec, which is what proves the
plugin does not break the deployed surface — and nothing more than that.

## The classroom around the call

A class has a bell. A video call does not, and a lesson held in one runs
over because nobody in it can see the clock the timetable is keeping.

So the screen carries its own controls under the call — Mute, Camera
off, Leave, and the class clock: elapsed against the timetabled length,
a bar, and the minutes remaining in words. They are Flutter rather than
Jitsi's own toolbar because that toolbar lives in the iframe and scales
with it; at phone width it becomes a row of icons a ten-year-old has to
guess at. These are labelled and they wrap.

`ClassClock` is pure and takes `now` as an argument, so the behaviour
that is easy to get subtly wrong is under test: elapsed never runs
backwards on a device whose clock is behind the server's, remaining
floors at zero rather than counting past the bell, and the bar clamps.

The teacher's classroom gets the timetabled length from the schedule
block. **A student's does not** — their mark carries when the lesson
started, not what the timetable gives it — so a student sees elapsed
time and no countdown. `remainingLabel` returns null rather than a
sentence saying there is no set length, because that would be a claim
about the timetable rather than about what the screen can see. The bell
is the teacher's to keep.

Mute and Camera off mirror their state locally rather than reading it
back from Jitsi: the iframe API reports those through events, and a
control that waits for a round trip before it looks pressed feels broken
on a school's connection. Leave hangs up *before* popping — popping
alone tears the iframe out of the page with the conference still joined,
which leaves somebody in a room nobody can see them in.

Chat, screen share, raise hand and tile view are Jitsi's own, in the
call's toolbar. Rebuilding them in Flutter would mean rebuilding
WebRTC.

## What the classroom mock asks for that is not built

The reference design is a full tutoring classroom: a work area beside
the call with tabs for **Whiteboard, PDF / image, Equations, Shared
document, Pronunciation** and **Session**. None of those are built, and
they are each a feature rather than a tab.

The whiteboard is the one worth naming a blocker for, because it looks
like the smallest and is not. A shared board needs a document both the
teacher and every student in the section can read and write. Today that
is not expressible in `firestore.rules`: a **student's** user document
carries no link back to their student record, so a rule cannot resolve
"which student is this uid" and therefore cannot ask "is this child in
this class". Only parents carry `linkedStudentIds`. Making a shared
board safe means first putting `linkedStudentId` on the student user
document — a schema addition, a migration for every existing student
account, and rules — and that is worth doing carefully rather than
quickly, since it is a new read path into children's data.

## Where the video is hosted

`JITSI_DOMAIN` — an Actions variable, passed to the build as a
`--dart-define`, defaulting to `meet.ffmuc.net`.

### It is not meet.jit.si, and that was not a preference

The public Jitsi was the original default and it cannot do this job. It
requires whoever creates a room to authenticate, and it no longer
welcomes being embedded by other sites — 8x8 sell embedding as a product
now. One cause, three complaints:

* a sign-in page,
* "waiting for a moderator",
* and the lesson opening in a browser tab instead of inside the app.

The iframe is refused, the screen falls back to handing the room to the
browser, and what the person meets over there is the sign-in. "Inside
the app" was never going to be true on that deployment.

The default is now a public Jitsi that asks nobody to sign in and is an
ordinary Jitsi install, so it embeds.

### And a school should still move off it

It is volunteer-run, free, and promises nobody anything. A school
putting its pupils' lessons through it is trusting a stranger's server
with minors on camera — no contract, no support, and no say if it
disappears on a Monday morning. Reasonable to start on, poor to run a
term on.

**The install steps are written down**: docs/42-hosting-the-video.md
takes a bare VPS to a token-only Jitsi the app embeds, in about ninety
minutes, and ends with the verification order that tells you which half
is wrong when something is.

Moving is one variable and no code change:

> Settings → Secrets and variables → Actions → **Variables**
>
> | | |
> |---|---|
> | `JITSI_DOMAIN` | `meet.yourschool.edu.ph` |

Set the matching `JITSI_DOMAIN` on the Functions side too and LogicClass
mints the tokens, so nobody signs in there either — see below. The two
must agree, or every token is rejected by a server it was not minted
for.

## Nobody signs in to the video

They already signed in — to LogicClass. So LogicClass says who they are,
in a token the deployment accepts, and the video call never asks.

This matters more than it sounds. The alternative is a pupil meeting a
Google, Facebook or GitHub sign-in on the way into their own school's
lesson: most children do not have one of those accounts, and the ones
who do would be handing a third party an identity to attend a class.

`issueMeetingToken` mints it, per person, per lesson. It re-asks the
access question rather than taking the room on trust — the caller names
a *session*, never a room, and the room is read from the document that
proves they belong in it: the session for staff, the student's own line
in the register for a child. A wildcard token is never issued, because
one would be a key to every lesson the school will ever hold.

The token carries a display name, whether this person runs the lesson,
and the one room. No email unless the account has one, no student
number, no section, no school name: a JWT is signed, not encrypted, and
everything in it is readable by anyone who sees the URL. Recording,
livestreaming and transcription are refused *in the token* rather than
hidden in the toolbar, because a hidden button is one a determined
teenager finds.

### Turning it on

Five environment variables on the Functions deployment. Set none and
nothing breaks: the app joins without a token, exactly as it did before
this existed — right on a deployment that asks for none, and Jitsi's own
sign-in on one that does.

| | |
|---|---|
| `JITSI_APP_ID` | the tenant. `app_id` self-hosted, the AppID on JaaS |
| `JITSI_APP_SECRET` | self-hosted: the matching `app_secret` (HS256) |
| `JITSI_PRIVATE_KEY` | JaaS instead: the RSA private key, PEM (RS256) |
| `JITSI_KEY_ID` | JaaS: the key's id, which goes in the JWT header |
| `JITSI_DOMAIN` | the deployment, for the `sub` claim |

A secret belongs in `firebase functions:secrets:set`, not in a variable
and not in this repository. A PEM pasted into an environment variable
arrives with its newlines escaped more often than not; the config reader
puts them back, so paste it as it comes.

Set `JITSI_DOMAIN` in **two** places — here for the token's `sub`, and
as the `--dart-define` above for where the app actually connects. They
must agree, or every token is rejected by a server that was not the one
it was minted for.

The client also turns off every sign-in-shaped control it can reach:
no prejoin page, no lobby, no profile section, no authentication UI in
the toolbar. Those are belt and braces. They hide a door; the token is
what means there is nothing behind it.

## Not verified here

**The live embed has not been run.** This environment's network policy
denies `meet.jit.si`, so `external_api.js` cannot be fetched and no
actual call has been made from this build. What has been verified is
everything up to that line: the rules the room lives by, the callable,
the clearing on all three paths, the demo matching the product, and the
app building and booting clean with the feature in.

The first real check is one person on a deployment: take a class online,
join as a student in another browser, press Time Out, and confirm the
student's screen loses the way in.

If a Content-Security-Policy is ever added to the site, Jitsi needs
`script-src` and `frame-src` for the configured domain. There is no CSP
today, which is why nothing here sets one.

## Covered by tests

| Layer | File | Covers |
|---|---|---|
| Pure | `meeting/room.test.ts` | a different name every time, nothing about the class in it, long enough not to be guessed, characters every deployment accepts, and a recogniser that refuses anything that arrived another way |
| Pure | `meeting/token.test.ts` | the two deployments' different names for `iss`/`aud`/`sub`; good for one room and never `*`; nothing about the child beyond a name; no empty email claim; the teacher moderator and nobody else; recording and streaming refused; it expires and allows for a server clock that is not ours; HS256 verifies against the secret and not a forged one; RS256 names its key; URL-safe throughout; an unconfigured or half-configured school yields no config at all |
| Emulator | `attendance-emulator/meetingToken.test.ts` | the teacher of the class as moderator, another teacher refused, the covering Admin allowed, a student on the register as a participant, a student who is not on it refused, an account with no student record refused, another school refused; a token never carries a room the caller did not earn; refused once the class comes back in person and for a room that did not come from this app; an unconfigured school gets no token *and* no relaxation of the access check; nothing written to the audit log |
| Emulator | `attendance-emulator/onlineClass.test.ts` | the room reaches every student's own line and only there; a fresh one each time; never written to the audit log; cleared by coming back in person, by Time Out, and for the absent student too; refused on a finished class; the teacher and the covering Admin only, never a student, never another school |
| Demo | `smoke/online_class_test.dart` | the same properties through the app's own repositories, plus what the student is shown — nothing when no class is on, the live lesson when their teacher starts it, nothing again once it ends |
| Pure | `unit/core/class_clock_test.dart` | elapsed never runs backwards on a slow device clock, remaining floors at zero rather than counting past the bell, the overrun is said rather than left as arithmetic, an unknown length claims nothing, and a zero-length class is not divided by |
| Widget | `smoke/classroom_controls_test.dart` | the classroom names its subject and section, offers a way in on a platform that cannot run the video, and fits a 360px screen at 1.3x text |
| Pure | `unit/core/meeting_domain_test.dart` | the default is not the deployment that refuses to be embedded, it is a bare host rather than a URL, and it is only a default |
| Widget | `unit/core/online_class_screen_test.dart` | the view is built before the meeting is started — the deadlock that made the screen spin forever; every failure landing on the fallback rather than the spinner (script refused, host absent, start refused, start throwing); the pass handed to the meeting, and absent rather than empty when the school has no key |
| Widget | `smoke/online_class_test.dart` | the Faculty Dashboard carries the Online Class tile, and the day's list offers Start online class on every class without clipping it off a phone-width card |
