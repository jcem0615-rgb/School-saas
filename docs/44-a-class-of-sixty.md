# A class of sixty

What it takes to hold a real class online, and why the shape of the call
decides it rather than the code.

## Two shapes, and only one of them scales

**Direct, between browsers.** Everybody sends their own video to
everybody else. Six people is five uploads each and thirty streams
across the room — an ordinary connection manages that. Sixty is
fifty-nine uploads from a single laptop and three and a half thousand
streams in the room. That does not go slowly at the edges; it fails.

**Through a media server (an SFU).** Everybody sends once, to the
server, which forwards. One upload each however many are in the room, so
a class of sixty costs a participant exactly what a call of six does.

A school teaching classes of sixty therefore needs the second, and no
amount of client code substitutes for it. What the app does is use one
when it is configured, fall back to the other when it is not, and never
pretend a direct call will hold a class — `peer_etiquette.dart` carries
both ceilings and the wording for hitting them.

## And it is finally, actually, inside the app

The second reason this matters, and it is the one that took a week to
arrive at.

Every embedded approach puts somebody else's page in an iframe, and a
server is entitled to refuse that. Two public Jitsi deployments were
tried on the deployed site: both serve `external_api.js` happily and
both then refuse the document inside the frame. It is a header —
`X-Frame-Options`, or a `frame-ancestors` policy — and nothing on this
side of an iframe reaches across it.

LiveKit is not an embedded page. It is a client library and a media
server; **LogicClass draws the video itself**, in Flutter widgets over
video tracks (`video_grid.dart`). There is no third-party document, so
there is nothing to be refused by.

## Setting it up

LiveKit Cloud has a free tier and there is no server to run; a
self-hosted LiveKit takes the same three values.

1. Create a project at **cloud.livekit.io**.
2. Copy the **project URL** (`wss://<something>.livekit.cloud`), an
   **API key** and its **API secret**.
3. **Actions → Variables** (the app needs only the URL, and it comes
   from the server with the pass, so there is nothing to set here).
4. **`functions/.env`**:

   ```
   LIVEKIT_URL=wss://<project>.livekit.cloud
   LIVEKIT_API_KEY=API…
   LIVEKIT_API_SECRET=…
   ```

5. `cd functions && firebase deploy --only functions`

That is the whole of it. The app learns the server's address from the
same callable that issues the pass, so moving to a different LiveKit —
or to a self-hosted one — is those three values and a Functions deploy,
with no rebuild of the site.

**Check the free tier against your numbers** before a term depends on
it. It is billed in participant-minutes and a class of sixty consumes
them sixty at a time.

## What the pass says

`issueMeetingToken` already decided who may join — the teacher from the
session, a student from their own line in the register — and now says it
in the form LiveKit reads:

* good for **one room**, named, so it cannot open another lesson;
* **no `roomCreate`**, so it cannot invent a lesson nobody is on the
  register for;
* `roomAdmin` only for the teacher, because a child who can remove the
  teacher from the lesson is a child who will;
* `canPublishData` off — chat between children, if it ever exists,
  belongs on the school's own record and not in an untracked side
  channel;
* identity is the uid, so a dropped connection rejoining **replaces**
  that person rather than leaving a ghost beside them.

## Two settings a class of sixty does not work without

Both default to off in the library, and both are on here.

**`adaptiveStream`** makes each device subscribe at the size it is
actually drawing, and stop subscribing to tiles that have scrolled off
screen. Without it, sixty participants means sixty full-resolution
streams decoded at once on a school laptop — not slow, frozen.

**`dynacast`** stops the *sending* side publishing quality layers that
nobody is currently looking at. That is the same saving taken off a
teacher's upload.

## Not verified from this repository

No token has been presented to a LiveKit server from here, and no call
has been made: this environment has no outbound access to one, the same
limitation that ran through the whole of this module. What is tested is
what the pass says and who gets one (34 tests over the token), the
ceilings and their wording, and the grid arithmetic that lays sixty
people out without crushing them into strips.

The first real check is one teacher and two browsers.
