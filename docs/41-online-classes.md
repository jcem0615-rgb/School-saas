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

## The teacher decides, not the timetable

Per session, by the teacher, because the reasons are same-day ones: a
typhoon, a suspension of classes, a teacher isolating. A school that has
to edit its timetable at 6am to hold a lesson will not hold the lesson.

The control is on the register, next to the roll, because that is the
screen the teacher already has open at the start of a class.

## What runs where

| Platform | What happens |
|---|---|
| Browser (the deployed PWA) | The meeting renders inside the app, in a platform view. |
| Android, iOS, Windows | The room is handed to the device — the Jitsi app if installed, the browser if not. |

The phone build hands off rather than embeds, and the screen says so
instead of implying otherwise. Embedding video on a handset wants a
native SDK (`jitsi_meet_flutter_sdk`), which is a dependency to add
deliberately and test on a real device rather than slip in behind a
seam. **The seam is built**: `MeetingLauncher` and the
`meeting_view_factory` conditional export are the same shape as
`install_prompt_factory` and `location_probe_factory`. Adding the native
SDK later means writing one more implementation and changing no screen.

## Where the video is hosted

`JITSI_DOMAIN`, a `--dart-define`, defaulting to `meet.jit.si`.

Configurable rather than hardcoded because which Jitsi a school uses is
a decision about their children's data, not about this app. The default
is free and needs nothing set up — good enough to try the afternoon a
typhoon closes the school, and not what a school should run a term on. A
school that cares points it at its own deployment or a paid tenant with
one build flag.

**Verify the public instance before promising it to a school.** Jitsi
has changed the terms of `meet.jit.si` more than once, including
requiring the first person into a room to sign in before it will start.
That is survivable for a teacher and fatal for a class of ten-year-olds,
and it is the kind of thing that is true or false on the day rather than
in documentation.

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
| Emulator | `attendance-emulator/onlineClass.test.ts` | the room reaches every student's own line and only there; a fresh one each time; never written to the audit log; cleared by coming back in person, by Time Out, and for the absent student too; refused on a finished class; the teacher and the covering Admin only, never a student, never another school |
| Demo | `smoke/online_class_test.dart` | the same properties through the app's own repositories, plus what the student is shown — nothing when no class is on, the live lesson when their teacher starts it, nothing again once it ends |
