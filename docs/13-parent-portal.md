# Module 9e: Parent Portal

## Overview

The lightest module in the build so far. Child Profile, Attendance
Monitoring, Grades, Statement of Account, Payment Monitoring, and
Announcements are all reuse — every one of those screens already existed
and already had parent-access rules written for it back when Payments
(Module 8), QR Attendance (Module 7), and Faculty Portal (Module 9c) were
built, specifically anticipating this. The only genuinely new code is
resolving *which* students a parent is linked to.

## The one new query: resolving "my children"

`AppUser.linkedStudentIds` has existed on the entity since Module 4 and
is populated by `provisionUser.ts`'s parent-linking validation (Module
10/Registrar Portal). `ParentRemoteDataSource.watchChildren()` takes that
list and resolves it to full `StudentSummary` records via a single
`where(FieldPath.documentId, whereIn: linkedStudentIds)` query — one
round trip regardless of how many children are linked (up to Firestore's
30-value `whereIn` limit, comfortably above any realistic family size).

`myChildrenProvider` watches `authStateProvider` rather than capturing
`linkedStudentIds` once, so if a Registrar links an additional child to
the account later, the parent's dashboard picks it up without requiring
a fresh sign-in.

## Confirming the whereIn query pattern against rules

This is the first module to query `students` with a `whereIn` on document
ID rather than a `get()` on a known ID or a `where` on an indexed field —
a meaningfully different shape than what earlier rules tests exercised.
`test-rules/parent-portal.rules.test.ts` seeds three students (two linked,
one not) and asserts the query returns exactly the two linked ones —
proving Firestore's per-document rule evaluation correctly filters an
`in` query down to only the documents the rule allows, rather than
rejecting the whole query or (worse) leaking the unrelated record.

## Payment Monitoring is read-only for Parents, by construction

`ChildDetailScreen` reuses `PaymentHistoryScreen` with `allowRefunds:
false` explicitly passed — the same screen Registrar and the student
themselves use, just with the refund action never rendered. Refund
authority stays exactly where Module 8 put it (Director/Admin only,
enforced server-side in `recordRefund.ts` regardless of what any client
UI shows), so this is a UI-layer convenience, not a new security boundary
to get right.

## Firestore collections

None new. This module is entirely composition of Registrar Portal
(`students`), Payments (`payments`), QR Attendance (`attendance`),
Faculty Portal (`grades`), and Director Portal (`announcements`) — all of
which already had parent-access rules in place.

## Testing

| Layer | File | Covers |
|---|---|---|
| Rules | `parent-portal.rules.test.ts` | `whereIn(documentId())` query correctly scoped to linked children only |

No new domain-layer unit tests: `WatchChildrenUseCase` is a pure
pass-through with no validation logic (the linking validation itself
lives in `provisionUser.ts`, already covered by inspection in Module 10's
docs — an emulator-based test for that specific validation path is
flagged as a QA follow-up alongside the other Admin SDK callables that
don't yet have dedicated emulator tests).

## Deferred to later modules

- **Notifications** (push alerts for new grades, low balance, attendance
  flags) — Notifications module.
- **Reports** — Reports module.
- **Multi-parent / guardian access to the same child** — the current
  model links children to individual parent accounts one-directionally;
  a shared-custody scenario (two parent accounts, one child) already
  works today since `linkedStudentIds` is per-parent-account, not
  exclusive — worth calling out explicitly since it wasn't obvious from
  the schema alone.

## Emergency alerts

When a child presses the emergency button, three things already happened
before this screen existed: the alert was written as a document,
`firestore.rules` granted the linked parents read access to it, and
`onEmergencyAlertCreated` resolved those parents server-side and pushed
to their devices. What was missing was the parent's own way to *look*.

That gap matters for exactly the reason the staff list exists. Push
cannot be relied on — permission gets declined, a service worker fails to
register, a phone is in a bag on silent, the project has no messaging
configured yet. Staff had a dependable in-app channel to fall back on;
parents had nothing. A parent who heard no notification and opened the
app had no way to find out.

**The banner is the point.** An unresolved alert paints across the top of
the parent dashboard, not behind an icon. A parent who opens the app for
any other reason — to check a balance, to read an announcement — is told
without having to go looking.

The parent's card is deliberately not the staff card. A parent cannot
acknowledge or resolve anything, so those buttons are absent. But the
acknowledged state is the single most reassuring fact on the screen, so
it is said in words rather than left as a colour a parent has no key to:

- `Sent to the school. Nobody has picked it up yet.`
- `Maria Santos from the school is on the way.`
- `Resolved by the school — brought to the clinic, ice applied.`

A parent reading "raised" would not know whether anybody had seen it.

The school's phone numbers sit on the same screen rather than one tap
away. A parent who has just read that their child pressed the button is
going to call somebody, and making them navigate to find the number is
the wrong thing to do to them.

`childrenEmergencyAlertsProvider` fans out one stream per linked child
rather than issuing a single query. That is the shape the rules allow: a
parent may read an alert whose `studentId` is in their own
`linkedStudentIds`, and a collection query cannot express that, because
Firestore rules reject queries rather than filtering them. Two children
is two small streams — the right trade against a denormalised copy that
could go stale in the one moment it matters.

The demo seeds one **resolved** alert from last week. A demo that always
opens with a child mid-emergency is alarming and stops being informative
after the first look; the live state is produced by pressing the button
as the student and switching roles, which is the flow worth watching.
