# Module 20: Data Protection

## Overview

The surface a school's Data Protection Officer asks about before signing.
It was the gap that blocked a signature rather than a demo: everything
else in this system was built to be *used*, and none of it was built to
be *asked about*.

Three pieces:

| Piece | Where |
|---|---|
| A privacy notice describing what this system actually holds | `PrivacyNotice`, rendered by `PrivacyNoticeBody` |
| An acknowledgement, recorded per person and per version | `privacyNoticeVersion` on the user record |
| A DPA, a privacy notice template and a retention schedule | `legal/` |

## What was removed, and what that means

Two of the original five pieces are gone: the **in-app data-request
queue** (`dataRequests`, its screens, its rules) and the **named Data
Protection Officer** stored on branding (`dpoName/dpoEmail/dpoPhone`).

This narrows the software, not the school's obligations. A school under
the Data Privacy Act still has to appoint a Data Protection Officer and
still has to answer access, correction, erasure and objection requests
within its stated window. What changed is only that this system no
longer holds the officer's contact details or tracks the requests: both
happen at the office, off this software, and the privacy notice now says
so rather than pointing at a screen.

The consequences worth knowing before this is sold:

- **A school cannot show, from this system, how it answered a request.**
  The refusal-with-a-reason record is gone, so that evidence lives
  wherever the office keeps it.
- **The privacy notice no longer prints a name to complain to.** It
  directs a family to the school office instead.
- **The going-live check no longer asks for a DPO.** Branding warns on a
  missing name, logo, school year or principal, and nothing else.

The `legal/` drafts still describe the officer and the rights in full,
because those are statements of law rather than descriptions of this
software. The privacy-notice template no longer tells a family they can
raise a request from their profile in the app, which stopped being true.

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

## Rules

Nothing in this module has a collection of its own any more. The
acknowledgement is an ordinary self-write to the user's own document,
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
| Demo | `data_protection_test.dart` | the gate opens off the record and not off a dismissed screen; an older version still owes a new acknowledgement; the acknowledgement survives a role switch |

## Deferred

- **A personal data export.** Producing the document — everything held on
  one student, printed — would be the obvious build if request handling
  ever comes back into the software. The report PDF machinery is already
  there for it.
- **Breach notification workflow.** The DPA commits to a notification
  window; nothing in the app tracks one.
- **Per-school notice text.** The notice describes the software, which is
  the same for every school. A school wanting its own wording in the app
  would need it stored per tenant and versioned per tenant.
