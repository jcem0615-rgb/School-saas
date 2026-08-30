# Module 17: Notifications

## Overview

When the school has something to tell somebody — a suspension notice, a
guidance appointment, an emergency raised by their child — it reaches
them two ways, and the order matters:

1. **An inbox item**, at
   `schools/{schoolId}/notifications/{uid}/items/{itemId}`. This is the
   dependable channel. It survives a phone that was off, a browser that
   never granted permission, and a token that went stale three weeks ago,
   and it is still there tomorrow.

2. **A push notification** to whatever devices that person has
   registered. This is the fast channel, and it is best-effort by design.

Before both existed, "notify" meant only the second. A parent whose phone
was in a bag during a suspension notice had no way to find out that one
had been sent — nothing was recorded anywhere they could read.

The app is installable as a PWA, so "their phone" means a home-screen
icon on Android/desktop Chrome, and Safari on iOS 16.4+ once the user has
added it to the Home Screen.

## What is built

**One delivery path** — `functions/src/shared/notify/deliver.ts`. Every
trigger that notifies anybody goes through it: write the inbox items,
push to the tokens, prune what FCM says is dead, never throw. A push
failure must not fail the trigger, because a thrown trigger is a retried
trigger and a retried fan-out notifies everybody a second time.

**What notifies, today**

| Source | Trigger | Who is told |
| --- | --- | --- |
| Announcement posted | `triggers/announcements/onAnnouncementCreated.ts` | Active users in the addressed roles |
| Emergency alert raised | `triggers/emergency/onEmergencyAlertCreated.ts` | The section's adviser and the student's parents |
| Summons issued or cancelled | `triggers/guidance/onSummonsWritten.ts` | The student's own account and every linked parent |

**Targeting for announcements** —
`functions/src/shared/announcements/audience.ts`. The same rule as
`AnnouncementAudience.includes` on the client, kept separate on purpose:
the client decides what a list shows, this decides whose phone rings at
5am. Both are covered by tests asserting the same table of cases, which
is what keeps them from drifting.

**The inbox, in the app** — `app/lib/features/notifications/`. A bell in
every school-scoped portal's app bar carrying an unread count, and
`/notifications`, which lists everything newest first. Every push links
there rather than to a role-specific screen: a link into a screen that
exists for one role is a link that breaks for everybody else.

**Device tokens** — `schools/{schoolId}/users/{uid}/deviceTokens/{token}`.
One document per device, keyed *by* the token so re-registering the same
browser overwrites rather than accumulating a row per launch.

A subcollection rather than a field on the user document, and the reason
matters: `users/{uid}` is readable by everyone in the school, and anyone
holding a token can push to that device. The rule on `deviceTokens`
restricts read and write to the owner. Triggers use the Admin SDK, which
bypasses rules.

**Registration** — `PushRegistrar` (`app/lib/core/push/`), a port with an
FCM implementation and a no-op used in demo mode and tests. Sign-out
unregisters, because school computers get shared and the next person must
not inherit the last person's notifications.

## Deliberate choices

**Permission is asked on the notifications screen, not at launch.** A
permission prompt in front of somebody who opened the app to check a
grade is a prompt that gets dismissed — and a dismissed browser prompt
cannot be asked again from code. The next one has to come from the person
themselves, in site settings, which almost nobody finds. So the ask sits
on `/notifications`, where notifications are what they are already
looking at, alongside a plain statement that everything appears on that
screen either way. Profile → Notifications still has the same toggle.

**The uid is in the path, not in a field.** There is no query anybody can
write from the app that returns somebody else's notifications. A flat
collection with a `userId` field would need a rule to defend every read,
and one screen that forgot the filter would hand a parent every other
family's alerts.

**A recipient may mark it read and nothing else.** `firestore.rules`
allows an update only when the affected keys are `isRead` and `readAt`.
Without that check, "mark as read" is also "edit the summons you were
sent to say a different date". Creation and deletion are refused
outright: a client that could create these could post a notice in a
colleague's inbox that appears to come from the school, and one that
could delete them could clear the record that a summons was ever sent.

**Inbox items are created, not set.** A Cloud Functions trigger is
delivered at least once. The document id is derived from the kind and the
source id, so a second delivery fails with ALREADY_EXISTS — which is
swallowed — rather than quietly marking an already-read notification
unread again. Where one source can legitimately notify twice, the caller
distinguishes them: a cancelled summons uses `${summonsId}:cancelled`.

**Creation only, not edits.** Correcting a typo in a suspension notice
should not buzz eight hundred phones a second time. The one exception is
a summons being **cancelled**, which is notified deliberately: a family
that rearranged a working day around an appointment should not turn up to
one that is off. A summons being *completed* is silent — the student was
there.

**A malformed audience reaches nobody, not everybody.** `readAudience`
fails closed on a missing, non-object, or non-array audience, and only
accepts a literal `true` for `all`. A push cannot be unsent: reaching
nobody is a bug someone reports, while pushing a payroll notice to every
parent in the school is not recoverable.

**Dead tokens are pruned on send.** FCM reports unregistered tokens per
recipient; those documents are deleted. Without it the token list grows
forever with every reinstall and cleared browser.

**Sends are chunked at 500 tokens.** `sendEachForMulticast` rejects more
than that outright. A school large enough to cross the line is a school
whose announcements would otherwise silently stop going out.

**The push body is truncated to 180 characters; the inbox item is not.**
A push preview is a lock-screen line. The whole message is one tap away.

## Setup required before push works

Three things are per-project and are *not* checked in, because they
belong to whoever deploys this. The **inbox works without any of them** —
only the push half is affected.

1. **`app/web/firebase-messaging-sw.js`** — replace the `REPLACE_ME`
   values with your Firebase web config (Project settings → General →
   Your apps → SDK setup and configuration). These are public identifiers
   already shipped inside `main.dart.js`; they grant nothing on their own.
   This file is not generated by `flutterfire configure`, so it has to be
   filled in by hand once.

2. **A VAPID key** — Project settings → Cloud Messaging → Web Push
   certificates → Generate key pair. Pass it at build time:

   ```
   flutter build web --release --dart-define=VAPID_KEY=BN...
   ```

   Also public: it identifies the project to the browser's push service.

3. **Deploy the triggers**

   ```
   firebase deploy --only functions:onAnnouncementCreated,functions:onEmergencyAlertCreated,functions:onSummonsWritten
   ```

## What is covered by tests

* The rules — `test-rules/notifications.rules.test.ts`: a recipient reads
  their own and nobody else's, an admin cannot read a family's, a
  suspended school's inbox is closed, marking read is allowed and
  rewriting the text is not, and no client may create or delete.
* The wording — `functions/test/shared/notify/summonsMessage.test.ts`:
  Manila time rather than the server's, and a sentence that still reads
  correctly with no reason or no date on the record.
* Who is told — `app/test/smoke/notifications_test.dart`, against the
  demo repositories, which mirror the triggers: a summons reaches the
  student and their parent and not the registrar, cancelling notifies
  again, completing does not, and one account marking theirs read does
  not touch another's.

## What is not covered by tests

Actual delivery. No test in this repo proves a notification arrives on a
real handset — that needs a live Firebase project, a real browser
granting permission, and a device. Verify it by hand once after the setup
above, with two accounts in different roles, and check that the one *not*
addressed stays silent.

## iOS caveat

Safari only delivers web push to a PWA that has been added to the Home
Screen, on iOS 16.4 or later. In a normal Safari tab there is no push at
all, and there is nothing this app can do about that. Android Chrome and
desktop Chrome/Edge work from an ordinary tab. The inbox is unaffected —
it is an ordinary Firestore read and works everywhere the app does.
