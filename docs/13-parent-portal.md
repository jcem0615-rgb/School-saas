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

## How a parent account comes to exist

Added after the fact, and the gap it closes was larger than a missing
field: **there was no way to create a parent account at all.**

`provisionUser.ts` had accepted `role: 'parent'` with `linkedStudentIds`
since the module was written, firestore.rules read that array on every
parent path, and everything in this document worked. But no screen in the
app ever called it, and nothing ever wrote `linkedStudentIds`. The portal
was complete and unreachable: on real Firebase a school could not have
onboarded a single family. Only the demo had parents, because the demo
seeds them directly.

Two paths, from the student's own record (Registrar → a student → Family
Portal Access):

- **Create Parent Portal Account** — pre-filled from the guardian already
  written on the record, since that is where the family's name, number and
  address already are. The account is created *and linked to this child in
  the same step*: an account with no children can sign in and read
  nothing, which looks broken and generates a phone call.
- **Link an existing parent** — found by email. This is the second-child
  case, and it is not optional. Without it a mother enrolling her second
  child is told the address is already taken, the office invents a second
  address for one person, and then neither account shows her both
  children.

The screen lists who can currently see the child, read straight from
`linkedStudentIds` — so it is the school's real answer to "who can read my
child's marks?", not a second list that could drift from the one the rules
resolve against. Removing access says whether it is that parent's only
child, because unlinking the last one leaves an account that can sign in
and see nothing.

## linkedStudentIds is a permission list, not a profile field

Every parent read in firestore.rules — grades, attendance, the statement
of account, guidance summons, emergency alerts, the messaging thread —
resolves to "is this studentId in `users/{uid}.linkedStudentIds`?".
Nothing else gates it.

The two failure directions are not symmetrical. A missing link is an
inconvenience: a parent rings the office and somebody adds it. A wrong
link hands one family another family's child — their marks, their
attendance, their balance, and a private line to their teacher — and
nothing on either screen looks unusual afterwards.

The rule that lets a Director or Admin edit a user document is a
**denylist**, so until `linkedStudentIds` was added to it, either of them
could make that grant with a client write that nothing recorded.
`setParentLink.ts` is now the only writer:

- caller must be director, admin or registrar (faculty and guidance are
  deliberately absent — a class adviser knowing a family is not the same
  as being allowed to grant access to a child's record);
- the parent must exist, at this school, and actually have `role: parent`
  — refused rather than allowed-and-ignored, because a `linkedStudentIds`
  on a faculty account does nothing today and would silently become a
  grant the day any rule stopped checking the role first;
- the student must exist, so an access list cannot hold a row nobody can
  evaluate;
- linking somebody already linked returns `changed: false` and writes
  nothing, so the audit log does not fill with links nobody made;
- everything else lands in the audit trail with a sentence naming who
  granted what, about whom.

`test-rules/parent-links.rules.test.ts` pins the refusals, including the
one worth stating: an admin cannot smuggle the field through inside an
edit that is otherwise allowed.

## Contact details

Parent accounts carry a `phone` like every other account now, written by
`provisionUser` at creation. Before this, the only way a number reached a
user document was the person editing their own profile — which requires
signing in, which is the thing a password reset by phone exists for. See
`docs/10-registrar-portal.md`.
