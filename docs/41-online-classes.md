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

## The timetable is not the whole of a school year

A teacher can hold an online class for any class they take, on any day,
whether or not the timetable has a row for it today.

It has to work that way. The lessons most worth holding online are
exactly the ones no timetable anticipates: the make-up for the day a
typhoon closed the school, the review session on the Sunday before an
exam, the class moved because the hall was needed. A feature that is
available only when the timetable already expected the lesson is
unavailable on the days it is most wanted.

**Faculty Dashboard → Online Class → the camera button in the bar**, or
the button on the empty day, opens a list of every class the teacher
takes — one row per subject and section, not one per timetable slot.

The guard on the day's list is unchanged, and deliberately: a stale
screen, or a phone that slept through midnight, must not file a day's
marks against a class that is not running. Stepping around it is a
separate, explicit request (`unscheduled: true`), and the server refuses
it otherwise. It is not a way around whose class it is — another
teacher's class is still refused.

The register is filed under the day the lesson actually happened, and
carries `unscheduled: true`, which the audit log repeats in words.
"Why is there a Mathematics register dated a Sunday" gets asked of the
record months later, by somebody who cannot ask the teacher.

## Where the video is held

Through a media server the school connects, and **LogicClass draws the
video itself** -- Flutter widgets over video tracks, no embedded page.

That is one decision doing two jobs. A media server means everybody
sends one stream rather than one per classmate, which is what carries a
class of sixty. Drawing it ourselves means there is no third-party
document, so no server can decline to be embedded -- which is exactly
what ended the previous approach.

The embedded path is gone. Two public Jitsi deployments were tried on
the deployed site and both refused the frame; a header on somebody
else's server is not something client code reaches across, and keeping a
fallback that could not work meant lessons broke instead of saying so.
Unconfigured now says: *online classes are not set up yet.*

Three values on the Functions deployment, no rebuild of the site, and
the server's address travels with the pass. See
**docs/44-a-class-of-sixty.md**.

## How long a lesson runs

As long as the teacher runs it. The clock counts up and there is no
limit: a lesson is not over because an hour passed, and a screen telling
a teacher in front of thirty children that their time is up is making a
decision that is not its to make.

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

There is no Content-Security-Policy on the site. If one is ever added,
the lesson needs `connect-src` and `media-src` for the LiveKit host in
`LIVEKIT_URL` — the video is drawn by this app in its own widgets, so
there is no frame to allow and nothing to be refused embedding.

## What a pupil has in the lesson

**A hand, and four answers.** Sixty microphones opening at once is not a
lesson, so a class that cannot interrupt has to be able to signal.
**Raise hand** stays up until it is taken down — by the pupil, by the
teacher, or by the lesson ending — because a hand is a request that has
not been dealt with yet. Beside it are four one-tap answers: 👍 Yes, 👎
No, 🐌 Slower, 😕 Lost. A reaction shows for six seconds and then goes,
because a "yes" still showing four questions later is worse than no
answer.

Both appear on the face that sent them and in the teacher's class list.
The teacher can lower one hand or all of them.

### Why a pupil can do this when the data channel is shut to them

They do not send a message. They set a **participant attribute** — one
small labelled value, set on themselves, replacing whatever was there.

The difference is the whole reason the token stayed shut. An attribute
cannot be addressed to one child, cannot accumulate, cannot carry a
conversation, and everything in it is visible to the teacher and
attributable to whoever set it. `canPublishData` — an actual channel
between children — is still the moderator's alone. `canUpdateOwnMetadata`
is what a hand needs, and it is all a hand gets.

And it is read the way a form is read rather than the way a message is:
a hand is a timestamp or it is nothing, a reaction is one of four names
or it is nothing, and a time outside what a lesson could hold is
discarded. A pupil who worked out how to put words in the field would
find that nothing renders them.

The teacher lowering a hand goes the other way, on the channel only a
teacher can send on: nobody can reach into somebody else's attributes,
so each device lowers its own when it sees its name — or the star that
means everybody.

## Getting in: four locks, and why none is enough alone

A teacher can hand out a **link**. The link gets forwarded into a class
group chat, screenshotted, posted. So the link is an address and nothing
else — which school, which lesson — and **everything that decides who
comes in is decided on the server**, after the person has signed in:

| # | Lock | Where it is enforced | What it catches |
|---|---|---|---|
| 1 | **The school** | `requireSameSchool`, from the caller's own claims | Another school's account following the link |
| 2 | **The register** | a line of their own, `subjectAttendance/{sessionId}_{studentId}` — or the lesson is theirs to teach | Anybody who is not in this class |
| 3 | **The code** | `meetingPasscode` on the session, read out at the start | The account that is not the person holding the phone |
| 4 | **The scope** | section, grade level, department, education level, programme — compared against the record **as it stands now** | A child who has since been moved, promoted, transferred or withdrawn |

**The link never carries the room name or the code.** The room name is
what the media server actually accepts; the code is the second lock. A
link that carried either would be a single forwarded message that puts a
stranger in a room of children. The Invite panel has two buttons for
that reason, and the message it writes says *"You will need the class
code. I will read it out at the start."*

### The code

Eight characters of Crockford's base32 — no I, no L, no O, no U. Three
of those because a code read aloud to a ten-year-old must not turn on
whether a character was a one or an ell; the fourth so that eight random
characters cannot spell something a teacher then has to read to a class.
Reading it back is forgiving in the same spirit: I and L are taken as 1,
O as 0, the dash and the shift key are ignored.

It is minted with the room and cleared with it — a code left on a lesson
that has come back in person is a code still being read out for a door
that is shut. It lives on the session document, which is staff-only in
`firestore.rules`, and is **never** copied onto a pupil's mark, where
the room goes. The teacher is never asked for it: they set it, and a
teacher locked out of their own lesson by their own code is a lesson
that does not happen.

Eight wrong codes and the door stops answering that person for ten
minutes. Counted **per person per lesson**, deliberately — locking the
lesson would hand any pupil in the class a way to shut the rest of them
out of it. The counter lives in `meetingAttempts`, which
`firestore.rules` denies to everybody: a client that could read it would
learn how many guesses are left, and one that could write it could give
itself more.

### The scope

A register is a photograph of the roll when the lesson opened. Student
records are not: children are promoted, moved between sections mid-year,
transferred between departments, switched between strands, withdrawn.
Every one of those leaves an old mark pointing at a lesson the child is
no longer part of.

So `openClassSession` stamps the lesson with the scope of the roll it
was built from, and the door compares the person standing in it against
that scope *now*. The scope is a **set** per dimension rather than a
value: today a roll comes from one section, but an elective, a college
course or a remedial group pulled from three sections is one lesson with
several sections in it, and a scope that could hold only one value would
have to be abandoned the first time a school ran one.

**An unrecorded dimension is not a refusal.** Sessions opened before
this existed carry no scope, and students enrolled before a field
existed carry no value for it; refusing those would lock a school out of
its own lessons to enforce a rule about records that have not moved. The
section is checked always — every lesson and every student record has
always had one. The rest are checked when the lesson names them and the
person has a value for them.

The scope is checked **before** the code, so somebody who does not
belong here is told they do not belong here rather than invited to guess
a code first.

## What a teacher has in the lesson

Three things beyond the microphone and the camera.

**Choosing a camera.** A school laptop has a built-in camera and often a
better one on a USB lead; a phone has two. The browser hands over
whichever it likes first, which is not reliably the one pointing at the
teacher. The **Camera** button swaps between them mid-lesson, without
rejoining and without disconnecting anybody, and remembers the choice
for next time. A camera unplugged since the last lesson falls back to
one that is there rather than leaving the lesson with no picture.

**Blurring the background.** The same panel offers it, and tells the
truth about it. The blur is not something this app draws: it is a
property of the camera, provided by the operating system — Windows
Studio Effects, macOS, a Chromebook — and most school hardware does not
have it. Browsers accept the request and then leave the picture exactly
as it was, so the switch is flipped, the camera is asked what it is now,
and the answer is believed. Where it cannot be done the switch says so
in words a teacher can act on, rather than sitting in the "on" position
over an unchanged room.

**Seeing the class.** A **Class** button in every lesson opens the room
as a list: who is here, when each of them joined, whose microphone and
camera are on, who is sharing, and — at the top — whose hand is up and
in what order. A grid of sixty tiles answers "is everybody here" badly
and "who put their hand up first" not at all. The button itself carries
the count, and switches to the number of hands the moment there is one.

The join time is there because a child who came in twenty minutes late
is something a register should show, and a tile that looks exactly like
everybody else's does not show it.

**Sharing a screen, and drawing on it.** **Share screen** puts a window
in front of the class; the shared window takes the large tile and the
faces move to a strip along the edge — down the side of a wide window,
underneath a tall one. The shared window is contained, never cropped: a
spreadsheet with its last column cut off has failed at the thing it was
shared for.

While something is shared, the teacher gets a **pencil**, a **rubber**,
four colours and **Clear**. The tools appear with the screen and go away
with it, because a pencil over a lesson with nothing shared draws on
nothing, and a tool that does nothing when pressed is a tool a teacher
stops trusting.

Three decisions make the board work, and each of them is the answer to a
way it would otherwise be broken:

- **A mark is a fraction of the tile, never a pixel.** The teacher draws
  on a laptop and a pupil watches on a phone held sideways. The tile is
  forced to 16:9 on every device, so those fractions mean the same
  thing everywhere — and a shared window that is not 16:9 letterboxes by
  the same amount on every device, so the marks still land on the same
  word.
- **A stroke travels once, when the hand lifts.** Sending every touch is
  sixty packets a second to sixty people. The person drawing sees their
  own line immediately, from their own hand, and is the only one who
  would notice the difference.
- **Erasing sends the ids it removed, not the shape of the rubber.**
  "Remove these three" lands identically on every device; "rub here,
  this hard" does not.

A pupil who joins ten minutes in is sent the board as it stands,
otherwise they would see a clean slide with the teacher talking about a
circle that is not there.

**Only the teacher draws.** Sixty pupils with a pencil over a shared
screen is not a lesson. The tools are not offered to anybody else, the
board refuses their strokes if a future screen forgets to hide them, and
the token settles it: `canPublishData` is granted to the moderator and
to nobody else. Receiving needs no permission, so a class sees the
teacher's pencil without being able to hold one — which keeps the rule
the token was always making, that there is no untracked side channel
between children.

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
| Widget | `unit/core/online_class_screen_test.dart` | a minute of clock ticks rebuilds no part of the call, and neither does pressing Mute; the clock reaches the bar through a notifier rather than the screen's state; | the view is built before the meeting is started — the deadlock that made the screen spin forever; every failure landing on the fallback rather than the spinner (script refused, host absent, start refused, start throwing); the pass handed to the meeting, and absent rather than empty when the school has no key |
| Widget | `smoke/online_class_test.dart` | the Faculty Dashboard carries the Online Class tile, and the day's list offers Start online class on every class without clipping it off a phone-width card |
| Pure | `unit/core/whiteboard_test.dart` | a rubber finds a line it is held against rather than only its recorded points; a stroke survives the wire and back; damaged messages are refused rather than half-read; the board drops its oldest once full and replaces a stroke that arrives twice; a long stroke stays under what LiveKit will carry; two devices that saw the same messages hold the same board |
| Pure | `unit/core/board_controller_test.dart` | nothing is drawn until a tool is picked up; the line shows under the finger before anybody else has it, and travels once when the hand lifts; a tap is a dot with enough length to be rubbed out; the rubber says nothing when dragged over empty space; a pupil cannot draw whatever the screen offers them; a latecomer is sent the board; nonsense from the network is ignored, not thrown |
| Pure | `unit/core/stage_test.dart` | a shared screen takes the large tile and my own share wins over somebody else's; two shares at once settle on one rather than flickering; the strip stays within what a face needs; a remembered camera is used when it is still plugged in and fallen back from when it is not; an unlabelled camera is still a choice; a document camera is not mirrored; the blur switch believes the camera and says why when it cannot |
| Pure | `unit/core/invite_link_test.dart` | the link carries no room name, no code and no token; it drops whatever the page it was copied from was carrying; it goes wherever the app is served from rather than one hard-coded host; a truncated or malformed link reads as nothing rather than throwing; a link naming something that is not a document id is refused before it reaches a query; the message around it never sweeps the code in |
| Pure | `unit/core/class_passcode_test.dart` | the Dart and the TypeScript agree about the alphabet and the length, read out of the TypeScript rather than copied; I, L, O and U are absent; an eye is taken for a one and an oh for a zero; a lesson with no code is not a lesson where the empty string is the code |
| Pure | `meeting/passcode.test.ts` | the same, from the server's side, plus constant-time comparison and a refusal of anything that is not a string |
| Pure | `meeting/scope.test.ts` | the scope of a roll is read off the records it was built from and holds every value when a lesson draws from several sections; a child moved section, promoted a grade, moved department or programme, or no longer enrolled is refused, each by name; a dimension the records never filled in does not lock a school out, and the section never is waived |
| Emulator | `attendance-emulator/meetingToken.test.ts` (the four locks) | the teacher is not asked for the code and a child on the register without it is refused; the dash and the shift key are forgiven; a lesson with no code still opens; the code never comes back in the answer, right or wrong; eight wrong ones close the door, the right one forgets them, and the lock falls on the guesser rather than the lesson; a child moved out of the section, grade, department or enrolment is refused with their mark still in place; an unscoped lesson is still joinable; the scope is checked before the code |
| Rules | `subject-attendance.rules.test.ts` (the counter) | the wrong-code count is unreadable and unwritable by the person it counts, and by every role in the school |
| Demo | `smoke/online_class_test.dart` (the code) | the demo mints the same shape, clears it with the room, never asks the teacher for it, refuses a pupil who does not have it and admits one who does |
| Pure | `unit/core/hands_test.dart` | a hand and a reaction survive the wire; an empty string is how a hand comes down, because attributes merge; anything that is not a timestamp or one of the four names is ignored, including a hand dated last week or next year; a reaction expires after six seconds but survives a clock that runs a little ahead; the teacher's list is hands first in the order they were raised, then everybody else by name, and does not reshuffle when two hands go up together |
| Pure | `unit/core/video_grid_test.dart` (the cap) | one person alone is not one face across a monitor; a phone still uses the width it has; a short window does not crop its only tile; a class of sixty still fills the window |
| Pure | `meeting/livekit.test.ts` (the grant) | a child may set their own attribute and may not publish data — the hand without the channel |
| Widget | `unit/core/online_class_screen_test.dart` (hands) | a pupil raises and lowers a hand and answers without unmuting; a reaction does not take their hand down; the teacher is offered neither, and is offered the class list, the count, and lowering one hand or all of them; a pupil is offered no way to lower anybody's |
| Widget | `unit/core/online_class_screen_test.dart` (controls) | sharing says nothing was shared when the teacher cancels the browser's chooser; the pencil appears with the screen and is put away with it; a pupil is offered none of it; the board reaches the call, so a stroke reaches the class; Clear is not offered over an empty board; the camera panel switches camera mid-lesson |
