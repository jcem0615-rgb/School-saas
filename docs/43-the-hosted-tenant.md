# The hosted tenant (8x8 JaaS)

The chosen path. No server to run, and embedding is the thing they sell
rather than something their server refuses — which is where two public
instances ended.

Maybe thirty minutes, most of it in a browser.

## Why this and not a public Jitsi

Tested, on the deployed site, twice:

| | `meet.jit.si` | `meet.ffmuc.net` |
|---|---|---|
| Serves `external_api.js` | yes | yes |
| Runs the class inside the app | **refused** | **refused** |

Both serve the script and then refuse the document inside the frame —
`X-Frame-Options` or a `frame-ancestors` policy on the app itself. It is
a server-side decision and nothing in this repository reaches across it.
8x8 host Jitsi as a product and embedding is what the product is for.

## What you need from them

1. Sign up at **jaas.8x8.vc**.
2. Note the **AppID**. It looks like `vpaas-magic-cookie-` followed by a
   long hex string. Everything else hangs off it.
3. Create an **API key**. Either let the console generate the keypair
   and download the private key, or make your own and upload the public
   half:

   ```bash
   openssl genrsa -out logicclass-private.pem 2048
   openssl rsa -in logicclass-private.pem -pubout -out logicclass-public.pem
   ```

   Upload `logicclass-public.pem`. Keep the private one: it is what
   LogicClass signs with, and anyone holding it can mint entry to any
   lesson.
4. Note the **key id** the console shows beside the key — it looks like
   `vpaas-magic-cookie-…/a1b2c3`. It goes in the JWT header, and without
   it every token is rejected with nothing useful said about why.

**Check the free allowance against your numbers** before a term depends
on it. It is a monthly active-user cap and it moves; one school may sit
inside it comfortably or not at all, and the console states the current
figure.

## What to set here

Two places, and they have to agree.

**The app.** Repository → Settings → Secrets and variables → Actions →
**Variables**:

| | |
|---|---|
| `JITSI_DOMAIN` | `8x8.vc` |
| `JITSI_TENANT` | your AppID, `vpaas-magic-cookie-…` |

`JITSI_TENANT` is the one that is easy to miss and fails quietly. A
hosted tenant puts every room beneath its AppID — the conference is
`<tenant>/<room>`. Send the bare room name and nothing refuses it: a
conference is created at the wrong path, the teacher sits in it alone,
every student sits in a different empty one, and it all looks like a
network fault.

**The Functions.** In `functions/.env` (gitignored; `functions/env.example`
is the shape):

```
JITSI_APP_ID=vpaas-magic-cookie-…
JITSI_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----
JITSI_KEY_ID=vpaas-magic-cookie-…/a1b2c3
JITSI_DOMAIN=8x8.vc
```

Paste the PEM as it comes — escaped newlines are put back by the reader.

Then deploy both. **Both**: the app asks for a token, and a callable
that is not there means no token, which means 8x8 turns the class away.

```bash
cd functions && firebase deploy --only functions
git commit --allow-empty -m "Rebuild against the school's tenant" && git push
```

## Verify, in this order

Each step tells you which half is wrong.

1. **A teacher starts a class and the video appears inside the app.**
   No sign-in, no lobby, no grey box.
   * Grey box or "has not started the class inside the app" → the
     domain or the tenant is wrong, or the build has not run yet.
   * A sign-in or "authentication required" → the token is not being
     accepted: check `JITSI_APP_ID` matches the AppID exactly, that
     `JITSI_KEY_ID` is the key id and not the AppID, and that the
     Functions deployed.
2. **A student joins from another browser**, signed in as a pupil on
   that register. Muted, with their real name.
3. **A student not on that register cannot.** They get no token and the
   app says they are not in that class.
4. **The teacher presses Time Out** and the student's way in
   disappears. The safeguarding one — it is what stops a class of
   children sitting in an unsupervised call after the lesson ended.

## What the token says

Built in `functions/src/shared/meeting/token.ts`, and it is already
JaaS-shaped: `iss: "chat"`, `aud: "jitsi"`, `sub:` the AppID, signed
RS256 with the key id in the header. A self-hosted Jitsi wants entirely
different values for those three, which the same file handles by
branching on whether a private key is configured — so nothing needs
changing if the school later moves onto its own server.

Each token is good for **one room, for four hours**, and carries a name,
whether that person runs the lesson, and nothing else. Recording,
livestreaming and transcription are refused in the token rather than
hidden in a toolbar.

## Not verified from this repository

No token has been presented to 8x8 from here — this environment has no
outbound access to any Jitsi, which is the same limitation that ran
through the whole of this module. What is tested is what the token says,
who gets one, and that the app sends it. The verification order above
exists because of that.

If you would rather not depend on 8x8 at all, the school's own server is
docs/42-hosting-the-video.md, and the same token code serves it.
