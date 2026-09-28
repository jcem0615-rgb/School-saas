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

## The demo can show it, without Firebase billing

A pass has to be signed with the API secret, a secret cannot live in a
browser, and the app's real signer is a Cloud Function -- which needs
Firebase's Blaze plan and a card. So for a while the demo showed every
part of holding a lesson except the lesson.

The site is already deployed on Vercel, so the smallest server that
solves it is one file there:
**`vercel/api/livekit-token.js`**. The deploy copies it into the
uploaded directory, the secret stays in Vercel's environment, and the
app asks for a pass at `/api/livekit-token` on its own origin -- no
CORS, no build flag, nothing to configure in the app.

### Switching it on

Three values, from LiveKit, pasted into Vercel. About fifteen minutes.

#### 1. Make a LiveKit project

**cloud.livekit.io** → sign up (GitHub or email) → create a project.
Pick the region nearest the school; for the Philippines that is
Singapore or Tokyo. Every participant's audio and video crosses to this
region and back, so distance is felt directly as delay.

#### 2. Take the three values

All three live under the project's **Settings → Keys** (the console's
wording moves; look for "API Keys" or the key icon).

**`LIVEKIT_URL`** — the project's WebSocket address. Shown on the
project page, sometimes labelled *Server URL* or *Project URL*.

```
wss://logicclass-3f9k2xd1.livekit.cloud
```

* It begins `wss://`, not `https://`. Pasting the `https://` form is
  the single most common way this fails, and it fails at connect time
  with nothing useful said.
* No trailing slash, no path.

**`LIVEKIT_API_KEY`** — create a key if the project has none. It is
short and begins with `API`:

```
APIx7dKm2Qw9RtB
```

**`LIVEKIT_API_SECRET`** — shown **once**, at the moment the key is
created. Copy it then; if you lose it, delete the key and make another.

```
wZ3n8Qs1FhK7pLdV2RtYxA4bN6mJ0cE5uS9gT1iO3kQ
```

Anyone holding this can mint entry to any room on the project. It goes
into Vercel and nowhere else — never into the repository, never into a
chat, never into the Flutter app.

#### 3. Paste them into Vercel

**Vercel → the `logicclass` project → Settings → Environment
Variables.** Add each one:

| Key | Value | Environments |
|---|---|---|
| `LIVEKIT_URL` | `wss://….livekit.cloud` | Production |
| `LIVEKIT_API_KEY` | `API…` | Production |
| `LIVEKIT_API_SECRET` | the secret | Production |

Production is the one that matters — the deploy publishes with `--prod`.
Ticking Preview and Development too is harmless.

#### 4. Redeploy, because variables do not apply retroactively

A deployment carries the variables that existed when it was made.
Adding them changes nothing until the next one. Either push any commit,
or go to **Actions → Deploy web → Run workflow**, which the workflow
allows on purpose.

#### 5. Check it, without signing in to anything

Open this in a browser:

```
https://logicclass.vercel.app/api/livekit-token
```

| What you see | What it means |
|---|---|
| `{"configured":true, …}` — **200** | The variables are set and the endpoint is live. Read `problems` — see below. |
| `{"error":"not configured"}` — **404** | The reply names which of the three are missing. **All three** means none reached this deployment: they were saved on a different Vercel project, or scoped to Preview instead of Production, or nothing has been deployed since saving them. **One** means that name is misspelled. |
| The LogicClass app loads | The rewrite is swallowing `/api`. Should not happen — `vercel.json` excludes it — but it would mean an old deployment. |
| Vercel's own 404 page | The endpoint was not bundled. Check the deploy log for "Bundled the demo token endpoint". |

A GET describes what the deployment holds and never mints a pass. It
prints no value — only lengths, prefixes and punctuation, so it is safe
to open from a phone in front of a class:

```json
{
  "configured": true,
  "values": {
    "LIVEKIT_URL": {"characters": 38, "scheme": "wss", "hadSurroundingSpace": false, "hadSurroundingQuotes": false},
    "LIVEKIT_API_KEY": {"characters": 13, "beginsWithAPI": true, …},
    "LIVEKIT_API_SECRET": {"characters": 43, "beginsWithAPI": false, …}
  },
  "problems": [],
  "verdict": "All three are the right shape. …"
}
```

`problems` is empty when nothing is visibly wrong. When it is not, each
line names one mistake and its fix. It catches the pair pasted into each
other's boxes, a secret shorter than the 32 characters LiveKit requires,
two values pasted into one box, and a `LIVEKIT_URL` that is a page in
the dashboard rather than the project's own address.

**When shape has nothing to say, the endpoint asks LiveKit.** Three
good-looking values taken from two different projects are
indistinguishable from their shape — so with `problems` empty, the GET
mints a throwaway, sixty-second `roomList` token from the same key and
secret and puts it to `LIVEKIT_URL` itself. LiveKit's answer comes back
under `livekit`, and its meaning in `summary`:

| LiveKit says | What it means |
|---|---|
| **200** | The three are a matching set. The fault is not in them. |
| **401** / **403** | They are not a set — the key and the secret are from different projects, or the secret was copied from what the dashboard displays rather than revealed in full. Its own words are quoted. |
| **404** | The address is reachable but is not a LiveKit project. |
| did not answer | `LIVEKIT_URL` is wrong, or the project is gone. Quotes the network error. |

Whatever LiveKit returns is stripped of the key and the secret before it
is repeated, in case a future version of it ever echoes one back.

A pass request never does any of this — a lesson starting does not wait
on a diagnostic — and neither does a GET that already found a problem in
the shapes.

`summary` is one line, written here, and the app prints it as it stands.
That is deliberate: this file deploys on its own, with nothing to
rebuild, so the wording of a diagnosis is minutes away rather than a
release away.

You do not have to come here to read any of that. When a demo class
fails to start, the failure card asks this endpoint itself and puts the
answer underneath the error — the problems if there are any, and
otherwise the three shapes and what their being right means. On a real
deployment it does not: a school's teacher can do nothing with it.

Values pasted with a trailing newline or wrapped in quotes are read
without them, so the commonest paste accident is no longer fatal. An
`https://` project address is dialled as `wss://`.

With `problems` empty, open a class: Faculty → Online Class → Start
online class.

### What the demo's pass does not do

It is not the product's security model and does not pretend to be. The
endpoint checks that the room looks like one this app generates and
nothing else, because there is no register behind the demo to check a
person against. Nobody is a moderator, so a stranger who found the room
cannot remove the person demonstrating it.

What keeps a stranger out of a demonstration is what keeps them out of a
real lesson: the room name is 120 random bits, generated per session,
and shown to nobody who was not given it.

It is also a token endpoint anybody who can reach the demo can call. For
a demo on a free LiveKit project that is a quota, not a breach -- but
use a throwaway LiveKit project for it, not the one a school will run
on, and rotate the key if the demo goes quiet.

**The real product does not use any of this.** With Blaze,
`issueMeetingToken` checks the register first -- the teacher from the
session, a student from their own line on it -- and this endpoint is
never called, because demo mode is the only thing that calls it.

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
