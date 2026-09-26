# Hosting the video yourself

A runbook for putting a school's online classes on a server the school
controls. About ninety minutes, most of it waiting for `apt`.

This is the end state the online-class module was built for. Everything
already in the app — the per-lesson room, the register that decides who
may join, the token LogicClass signs — assumes a Jitsi that will take a
token and will let itself be embedded. A public instance does neither
reliably, which is why the lessons have been fighting a sign-in page.

## What it gets you

| | Public instance | Your own server |
|---|---|---|
| Sign-in before a lesson | Yes, for whoever opens the room | **None.** LogicClass says who they are |
| Video inside the app | Refused by most | **Yes** |
| Who can enter a room | Anyone with the name | **Only a token this school signed** |
| Where the children are filmed | A stranger's machine | Yours |
| If it breaks on a Monday | Nobody owes you anything | Your server, your fix |

The third row is the one that matters most and is easiest to overlook.
Today the room name is the entire secret. On a token-only server, a
leaked room name is worth nothing without a signature only your Cloud
Functions can produce.

## What to buy

**2 vCPU, 4 GB RAM, Ubuntu 24.04 LTS or Debian 12**, on a plain public
IPv4 address. Roughly $6–12 a month. Take the nearest region —
**Singapore** for the Philippines: every participant's audio and video
crosses to this machine and back, so distance is felt directly as delay.

On capacity, treat these as starting points and measure, not promises:

* One class of 30–40 with video on is comfortable.
* Two or three classes at once is where 2 vCPU starts to strain. If the
  school intends to run a whole period online — six classes at once —
  budget 4–8 vCPU, or plan a second videobridge.
* Bandwidth matters more than people expect. Thirty pupils at modest
  quality is roughly 15–25 Mbps in *and* the same back out. Check the
  provider's bandwidth allowance, not just the port speed.

Whatever you buy, run one real class on it before a term depends on it.

## Before you start

You need a name and a record pointing at the server:

```
A    meet.yourschool.edu.ph    →    <the server's public IPv4>
```

Wait for it to resolve before installing — the certificate step fails
otherwise, and it fails late.

Everything below is run as root over SSH. Substitute your own hostname
for `meet.yourschool.edu.ph` throughout; it appears inside generated
config filenames, so a typo is tedious rather than fatal.

## 1. Name the machine and open the ports

```bash
hostnamectl set-hostname meet.yourschool.edu.ph

ufw allow 22/tcp      # keep your way in, first
ufw allow 80/tcp      # certificate issuance and renewal
ufw allow 443/tcp     # the site itself
ufw allow 10000/udp   # the media. this is the one people forget
ufw allow 4443/tcp    # media fallback, see below
ufw enable
```

**10000/udp is the video.** Without it the page loads, everybody sees
each other listed, and nobody sees or hears anybody — which reads as a
broken camera rather than a firewall.

**4443/tcp is worth opening for a school.** Filtered school and office
networks often block outbound UDP; this is the fallback Jitsi uses when
that happens. A school on a filtered connection is precisely this app's
audience.

## 2. Install Jitsi

```bash
apt update && apt install -y apt-transport-https curl gnupg2 lsb-release

curl -sSL https://prosody.im/files/prosody-debian-packages.key \
  | gpg --dearmor -o /usr/share/keyrings/prosody-debian-packages.key
echo "deb [signed-by=/usr/share/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/prosody-debian-packages.list

curl -sSL https://download.jitsi.org/jitsi-key.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/jitsi-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" \
  > /etc/apt/sources.list.d/jitsi-stable.list

apt update && apt install -y jitsi-meet
```

Two prompts:

* **Hostname** — `meet.yourschool.edu.ph`. Exactly the DNS name.
* **SSL certificate** — choose *"Generate a new self-signed
  certificate"*. A real one comes next; picking this now is correct, not
  a compromise.

Then get the real certificate:

```bash
/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
```

It asks for an email for expiry warnings. Give one a person reads: this
is the address that warns you before lessons stop working.

At this point `https://meet.yourschool.edu.ph/` should open and let you
start a meeting. It is wide open to the world — that is the next step.

## 3. Require a token

```bash
apt install -y jitsi-meet-tokens
```

It asks for an **APP ID** and an **APP SECRET**.

* App ID: `logicclass` (any stable string; it must match what the Cloud
  Functions send).
* App secret: generate one, do not invent one —

  ```bash
  openssl rand -hex 32
  ```

  Keep it. It goes into the Functions configuration in step 6 and
  nowhere else, and anyone holding it can mint entry to any lesson.

Check what it wrote, in
`/etc/prosody/conf.avail/meet.yourschool.edu.ph.cfg.lua`:

```lua
VirtualHost "meet.yourschool.edu.ph"
    authentication = "token"
    app_id = "logicclass"
    app_secret = "the value from openssl"
    allow_empty_token = false
```

`allow_empty_token = false` is the line that matters. True — or missing
— means a caller with no token at all is admitted, which is the whole
door left open with a lock fitted to it.

## 4. Shut the guest door

Token authentication on its own still lets guests in behind whoever
authenticated, through a second "anonymous" domain. For a school that is
the wrong default: it means anyone with the room name joins a class of
children, which is what the token was meant to stop.

In `/etc/jitsi/meet/meet.yourschool.edu.ph-config.js`, comment out the
anonymous domain if it is there:

```js
// anonymousdomain: 'guest.meet.yourschool.edu.ph',
```

In `/etc/prosody/conf.avail/meet.yourschool.edu.ph.cfg.lua`, comment out
the whole guest virtual host:

```lua
-- VirtualHost "guest.meet.yourschool.edu.ph"
--     authentication = "anonymous"
--     c2s_require_encryption = false
```

Restart the three services:

```bash
systemctl restart prosody jicofo jitsi-videobridge2
```

**Now verify the door is shut** before going further:

```
open https://meet.yourschool.edu.ph/some-room-name
```

It must refuse — an authentication prompt or an error. If it drops you
into a meeting, the token is not being required and every step after
this is decoration. Re-check `allow_empty_token` and that the guest host
is really commented out.

## 5. Let LogicClass embed it

The video appearing *inside* the app is an iframe, and a server can
forbid that. Check:

```bash
curl -sI https://meet.yourschool.edu.ph/ \
  | grep -i -E 'x-frame-options|content-security-policy'
```

If `X-Frame-Options` appears, that is the exact thing that put a dead
grey rectangle where the lesson should be. Edit
`/etc/nginx/sites-available/meet.yourschool.edu.ph.conf`: delete the
`add_header X-Frame-Options …` line, and add your site as a permitted
parent:

```nginx
add_header Content-Security-Policy "frame-ancestors 'self' https://logicclass.vercel.app" always;
```

Name your own site there. `frame-ancestors` with a list is a
restriction, not a hole: it permits LogicClass and continues to refuse
everyone else, which is better than the default of refusing everybody or
allowing anybody.

```bash
nginx -t && systemctl reload nginx
```

## 6. Point LogicClass at it

Two places, and they must agree. The app connects to the domain; the
Functions sign tokens naming it. A mismatch means every token is
rejected by a server it was not minted for, and the symptom is a
sign-in page — the thing you just did all this to remove.

**The app.** Repository → Settings → Secrets and variables → Actions →
**Variables**:

| | |
|---|---|
| `JITSI_DOMAIN` | `meet.yourschool.edu.ph` |

**The Functions.** In `functions/.env` (gitignored — see
`functions/env.example`):

```
JITSI_APP_ID=logicclass
JITSI_APP_SECRET=the value from openssl rand
JITSI_DOMAIN=meet.yourschool.edu.ph
```

Then deploy both:

```bash
cd functions && firebase deploy --only functions
git commit --allow-empty -m "Rebuild against the school's own Jitsi" && git push
```

The Functions deploy is not optional. The app asks for a token; a
callable that is not there means no token, which means the sign-in
comes back. (It will not stop the lesson — a missing callable degrades
to joining without a token — but it will not be the thing you wanted.)

### A note on where the secret lives

`functions/.env` is the simple path and it is what these steps use. The
value is then readable by anyone with Editor access to the Firebase
project. For a school that is usually one or two people and it is a
reasonable trade.

If you want it in Secret Manager instead — the right answer for a
larger deployment — it needs one code change as well as the CLI command,
because a v2 callable only sees a secret it declares:

```bash
firebase functions:secrets:set JITSI_APP_SECRET
```

```ts
// functions/src/callable/classSessions/issueMeetingToken.ts
import {defineSecret} from "firebase-functions/params";
const jitsiAppSecret = defineSecret("JITSI_APP_SECRET");

export const issueMeetingToken = onCall(
  {region: "asia-southeast1", secrets: [jitsiAppSecret]},
  …
);
```

Be aware that once declared, the secret must exist before *any* deploy
of this function succeeds. That is why it is not the default here.

## 7. Verify, in this order

Each step tells you which half is wrong, so do not skip ahead.

1. **`https://meet.yourschool.edu.ph/any-room` refuses you.**
   Tokens are required. If it lets you in, go back to step 4.
2. **A teacher starts a class in LogicClass and the video appears in the
   app.** No sign-in, no "waiting for a moderator", no grey box.
   * A card naming your domain instead → step 5, the framing headers.
   * A sign-in page → step 6, the two domains disagree, or the Functions
     were not deployed.
3. **A student joins from another browser, signed in as a pupil on that
   register.** They should arrive muted, with their real name.
4. **A student not on that register cannot.** They will not get a token;
   the app says they are not in that class.
5. **The teacher presses Time Out.** The student's way in disappears.
   This is the safeguarding one: it is what stops a class of children
   sitting in an unsupervised video call after the lesson ended.

## 8. Running it

**Certificates** renew themselves — the install script sets up a timer.
The warning email from step 2 is the backstop. A lapsed certificate
stops lessons outright.

**Updates**: `apt update && apt upgrade` every month or so. Jitsi moves
quickly. Do it in a school holiday, not during a term's first week, and
re-run the step 7 checks afterwards — an upgrade can reinstate the nginx
headers you removed in step 5.

**Nothing to back up.** No lesson is stored on this machine; the
register and the grades live in Firestore. If the server is lost,
rebuild it from this page and point `JITSI_DOMAIN` at the new one.
Keep the app secret somewhere the school will still have it — losing it
means re-running steps 3 and 6, not losing data.

**Watch the first real day.** `htop` and the provider's bandwidth graph
during a live period will tell you in ten minutes whether the machine is
the right size, and it is much cheaper to find out then.

## When something is wrong

| What you see | Where to look |
|---|---|
| Everyone connects, nobody sees or hears anyone | `10000/udp` is closed, or the server is behind NAT — see below |
| Works at home, fails at school | UDP is filtered; confirm `4443/tcp` is open |
| A sign-in page | The two `JITSI_DOMAIN` values disagree, or the Functions were not deployed |
| "Waiting for a moderator" | The teacher's token is not being read as moderator — check `app_id` matches on both sides |
| A card naming your domain, with "open in a tab" | The server refuses to be framed — step 5 |
| A grey box with the clock running | An older build; the app now detects this and shows the card instead |
| Certificate warnings | Renewal failed; check `systemctl status certbot.timer` and that `80/tcp` is open |

**If the provider gives the machine a private IP behind NAT** — some do —
media will connect and then drop. Add the two addresses to
`/etc/jitsi/videobridge/sip-communicator.properties`:

```
org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=<private IP>
org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=<public IP>
```

then `systemctl restart jitsi-videobridge2`. The installer usually
detects this; check here when video connects and dies.

Logs worth knowing: `journalctl -u prosody`, `-u jicofo`,
`-u jitsi-videobridge2`. Token rejections show in prosody's.

## Not verified from this repository

These steps are written from Jitsi's own packaging and the app's side of
the contract, which is tested. **No part of this runbook has been
executed from this environment** — it has no outbound access to a Jitsi
deployment, which is the same limitation that has kept the live embed
untested throughout. Expect the version-specific details — exact config
filenames, which headers the current nginx template ships — to need a
look rather than a copy-paste. The verification order in step 7 is there
because of that, not in spite of it.
