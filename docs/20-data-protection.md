# Module 20: Data Protection

## Overview

The surface a school's Data Protection Officer asks about before signing.
It was the gap that blocked a signature rather than a demo: everything
else in this system was built to be *used*, and none of it was built to
be *asked about*.

Five pieces:

| Piece | Where |
|---|---|
| A privacy notice describing what this system actually holds | `PrivacyNotice`, rendered by `PrivacyNoticeBody` |
| An acknowledgement, recorded per person and per version | `privacyNoticeVersion` on the user record |
| A named Data Protection Officer | `dpoName/dpoEmail/dpoPhone` on branding |
| A path for data subject requests, and the record of how each was answered | `dataRequests` |
| A DPA, a privacy notice template and a retention schedule | `legal/` |

## The notice is written from the collections, not from a template

Every category names what is held, why, **and who can see it**. That last
column is the question a family actually asks, and it is the one a
template answers with "authorised personnel". Here it says the guidance
office and the Director see guidance notes and teachers do not, because
that is what `firestore.rules` enforces.

The notice is data rather than prose in a widget, so the same words
render on screen and inside the acknowledgement gate, and a change to
them shows up in a diff. A notice nobody can diff is one nobody can tell
has changed.

## Acknowledgement, not consent

The record is that a person **was shown** the notice, not that they
consented to the processing. Those are different things and the
difference matters: a school processes student records because it needs
them to run a school and to meet obligations placed on it, not because a
twelve-year-old ticked a box. Calling it consent would imply the
processing stops if it is withdrawn, which is not true and would be a
worse position to defend than the honest one.

So the gate has no decline button. Declining would mean a student cannot
see their own grades, which is not a choice a school can offer. What the
notice gives is the right to ask, correct, object and complain — and
those are on the page, with the officer to take them to.

**It is a version, not a flag.** A flag would record the eight hundred
people who agreed to the old wording as having agreed to the new one,
which is exactly the record a regulator would object to. Bump
`PrivacyNotice.version` when the substance changes and everybody is asked
again; leave it alone for a typo.

The gate sits in `app_router.dart` beside the force-password-change
redirect, for the same reason: a notice somebody can navigate past is one
the school cannot say was given. Owner is exempt — the platform operator
is not somebody whose data the school processes, and there is no school
branding to name an officer from.

## Requests: the refusal is the feature

Four kinds — access, correction, erasure, objection — as separate kinds
rather than a free-text subject, because they are answered differently.

Closing a request **requires an outcome in both directions**. A school
genuinely cannot delete everything on request: a transcript is a record
it is required to keep and a receipt already reported cannot vanish. A
system with nowhere to put a refusal pushes the office into either lying
or ignoring the request, and the seeded demo deliberately shows a refusal
with its reason rather than a tidy queue of grants.

The queue sorts **oldest open first** and shows days waiting, flagging
anything past the school's target (defaulted to 15 days — the school's
own figure to argue with, not this software's statement of what the law
requires). A queue sorted newest-first is one where the request somebody
has waited a month for sinks out of sight, which is the only failure this
screen exists to prevent.

## Rules

```
schools/{schoolId}/dataRequests/{id}
```

- **Create**: anybody active in the school, for themselves only
  (`requestedByUid == request.auth.uid`), and never pre-answered — a
  queue you can pre-close proves nothing.
- **Read**: the office (Director, Admin, Registrar) and the person who
  asked. Not teachers: a teacher has no business in the list of who asked
  the school about their own records.
- **Update**: the office only, and the question itself is immutable —
  `requestedByUid`, `kind`, `details` and `requestedAt` cannot change
  when the answer is written.
- **Delete**: never.

The acknowledgement is an ordinary self-write to the user's own document,
permitted by `onlySelfEditableFieldsChanged`. It is a person asserting
something about themselves; what matters is that they cannot assert it
about anybody else, which the uid check already guarantees, and the rules
test pins that it cannot be smuggled in beside a role change.

## The `legal/` folder

Three drafts: a Data Processing Agreement between the operator and the
school, a privacy notice template for the school to adopt as its own, and
a retention schedule.

**They are drafts for counsel, and say so on every page.** The facts in
them — what is processed, who can read it, how it is protected, where the
functions are deployed — are accurate and are the part a lawyer cannot
supply. The clauses around them are ordinary and should be reviewed.
Every decision that belongs to the school or the operator is marked
`[LIKE THIS]`.

The roles are kept straight throughout: the **school** is the Personal
Information Controller and the **operator** is the Processor. That is why
there are two documents rather than one — a processor that writes the
school's privacy notice for it has misunderstood which of them is
answerable to the family.

## Retention is not automatic

Nothing deletes on a timer, deliberately. An automatic purge running
against a school's live records is a far worse failure than a record kept
too long: a school that loses a transcript cannot get it back, and the
student pays. Enforcing the schedule is a periodic human review, and the
schedule says so.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `data_request_test.dart` | overdue arithmetic, mandatory outcomes, every notice category naming who can see it |
| Demo | `data_protection_test.dart` | the gate opens off the record and not off a dismissed screen; an older version still owes a new acknowledgement; raise, answer and refuse |
| Rules | `data-requests.rules.test.ts` | self-only creation, never pre-answered, office-only answers, the question immutable, nothing deleted, acknowledgement cannot be made for somebody else |

## Deferred

- **A personal data export.** The access request is recorded and answered
  by hand today. Producing the document — everything held on one student,
  printed — is the obvious next build, and the report PDF machinery is
  already there for it.
- **Breach notification workflow.** The DPA commits to a notification
  window; nothing in the app tracks one.
- **Per-school notice text.** The notice describes the software, which is
  the same for every school. A school wanting its own wording in the app
  would need it stored per tenant and versioned per tenant.
