# Module 9a: Admin Portal

> **Since Module 39, the Admin operates the school.** Everything the
> Director used to be able to write is the Admin's: branding, settings,
> fee schedules, receipt booklets, expenses, payroll, programs, the
> timetable, teacher assignments, account creation and account status.
> Director and Principal read those screens and no longer edit them. See
> `docs/39-oversight-and-operations.md`.

## Overview

Covers Employee Management, User Approval, Reset Password, and Teacher
Assignment as new features. Announcements and Attendance Monitoring are
wired in as navigation entries into screens already built in earlier
modules (Director Portal and QR Attendance) — Admin's rules already
permitted these actions; this module just gives Admin a front door to
them.

## Design choice: no separate `employees` collection

`employeeInfo` (department, position, dateHired) already existed as an
optional field on `users/{uid}` since the Module 3 schema — every staff
role in this system has a portal account, so there's no scenario (unlike
Students) where HR data needs to exist independently of an account. Admin
Portal's "Employee Management" and "Employee Files" therefore extend the
existing `users` collection rather than introducing a parallel one. This
also means editing `employeeInfo` needed **no new backend code** — the
Module 4 rule already lets Director/Admin update any `users` field except
the security-sensitive ones (`role`, `schoolId`, `status`,
`mustChangePassword`), and `employeeInfo` was never in that exclusion list.

"Employee Files" in the sense of *documents* (contracts, certificates,
IDs) is a Documents module concern — this module only covers the HR data
fields, not file attachments.

## Who the Admin may create

The Admin creates **every role a school has, including another Admin.**

That last part is the whole point. An admin office is a department, not a
person. The earlier matrix let an Admin create a Principal, a Registrar,
a Faculty member, Staff and Guidance — everybody except a peer — which
meant a school whose one Admin resigned, went on maternity leave, or lost
the phone with their password on it had exactly one way to get another
Admin: ask us. The Owner account is the vendor's, and it was the only
other account in the system that could mint one. A school could not enrol
a student or run payroll until a support ticket came back.

The only role nobody may create this way is `owner`. There is one, it is
established by `bootstrapOwner` against a server-side email, and
`refuseProvisioning` refuses it for that reason specifically — separately
from the matrix — so that a future edit adding `"owner"` to some row by
accident still does not open it.

The decision lives in `functions/src/shared/auth/provisioning.ts`, on its
own and with no Firebase imports, so "can this person hand somebody else a
password" is a question that can be asked and tested without standing up a
Functions runtime. `provisionUser.ts` calls it and translates the refusal
into an `HttpsError`.

**The spreadsheet import is narrower on purpose.** Employee Management
imports a staff file, and `importableEmployeeRoles` stops at Registrar,
Faculty, Staff and Guidance. The form is one account at a time, typed,
with the role chosen from a dropdown in front of somebody; an import is
three hundred rows, and a role column reading `admin` all the way down —
a mistake, or a paste from the wrong sheet — would hand out three hundred
accounts that could each create three hundred more. Leadership accounts
are made one at a time.

## "User Approval" — implemented as account status management

This build provisions accounts (`provisionUser`, Module 4) rather than
accepting self-registration, so there's no incoming queue of unverified
signups to literally "approve." The equivalent control point — and what
Employee Detail's Activate/Suspend button exercises — is `setUserStatus`,
a new callable that flips a user's `status` claim and Firestore field.
Two guardrails worth calling out:

- **Self-protection**: a caller cannot change their own status (can't
  accidentally or maliciously lock themselves out).
- **Role hierarchy**: an Admin cannot suspend a Director's account —
  only another Director can. Prevents a lower-privilege role from
  disabling a higher one.

If a future module adds self-registration (e.g. Parent sign-up), this
callable is exactly the mechanism a real "approve this pending signup"
flow would call — the plumbing is already here.

## Reset Password

Wires the existing `resetPasswordAdmin` callable (built in Module 4) into
a button on Employee Detail. No new backend logic.

## Teacher Assignment

New collection, `teacherAssignments/{id}` (teacherId, subject, section,
schoolYear) — deliberately simple, following the same generic
create/read-by-role/no-delete pattern as Announcements/Meetings/Expenses
from Director Portal. Full **Schedules** (day/time/room grids) is a
related but distinctly larger feature, deferred — see below.

## The audit log (no screen, and that is deliberate)

**The log is written. It has no reader in the app.** There were two
screens over it — a full-school `AuditTrailScreen` for the Director and
the Admin, and a per-user `MyActivityScreen` on every dashboard — and both
were removed. Nothing about the writing changed: every callable still
calls `writeAuditLog`, and the `onAnyTenantDocWrite` trigger still fires
on every write to any direct subcollection of a school.

That is a strange-looking shape, so it is worth saying why it is the right
one. What the log is *for* is answering "who changed this grade" months
after the fact, when a parent asks the school — not browsing. A school
asked that question opens the export, or the console, or asks us; it does
not scroll a thousand-row list hoping to recognise the row. The screens
were the part that nobody used; the record is the part that matters, and
the record is intact.

The trigger is also what lets Announcements, Meetings, Approvals and
Expenses take direct client writes without each one needing a callable
purely to satisfy "every action must be logged" — so removing it would
have meant rewriting those, for a screen nobody opened.

### Who may read it

The read rule is unchanged. The Director and the Admin may read the whole
school trail; everyone else may read only the entries naming them. No
client code exercises either today. The grant stays because it is what an
export run under a school leader's own credentials uses, and what a screen
would need if one comes back — and because narrowing a person's access to
their own record is not an improvement to make as a side effect of
deleting a widget.

`'owner'` used to sit in that first list and never once matched: the rule
calls `hasRole()`, `hasRole()` requires `belongsToSchool()`, and the Owner
is platform-level with no `schoolId` claim at all. The rule read as though
the Owner could open any school's trail while the code said otherwise,
which is the wrong way round for a rule to be wrong — and the boundary the
dead branch pretended to cross is one this build deliberately does not
cross, the same call made about attendance in `07`. It was removed rather
than made to work. The rules suite pins the Owner out.

Nothing writes to the trail from a client, whatever the role.

### What it must never copy

**The audit log must never carry content that its own readers could not
otherwise read.** The trail is read school-wide by two roles, so copying a
document into an entry makes that document readable by both of them,
whatever the collection's own read rule says.

For one collection the read rule says the opposite in as many words.
`conversations` carries `lastMessage`, a preview of what a parent last said
to a teacher, rewritten on every message; the messaging rule says nobody
but the two participants may read a thread — not an admin, not the
director — and that a school needing to see one has a lawful-request path
"and an audit trail, not a back door". The audit trail was the back door.

`conversations` is therefore in `CONTENT_WITHHELD`: the entry is still
written, so who touched which thread and when is still on the record, but
the values are withheld and the entry says so in its remarks rather than
looking like a document that happened to be empty. Anything added to that
set later is held to the same invariant.

This is distinct from `EXCLUDED_COLLECTIONS` (`auditLog`, `notifications`,
`counters`, `users`), which are not logged at all — either they have
bespoke audit handling or they would cause runaway self-referential writes.

### Who deleted it

A hard delete has no `after`, so there is nothing left on the document to
read the actor from. The trigger used to fall straight through to
`"unknown"` — answering "who deleted this?" with the one word the trail
exists to avoid, on the single action where the answer matters most and is
least recoverable from anywhere else.

It now falls back to `before.updatedBy` / `before.createdBy`: the last
account to have written the document. That is not proof of who removed it,
which is why the entry says as much in its remarks rather than presenting a
name as a finding.

## Firestore collections added

```
schools/{schoolId}/teacherAssignments/{id}  -- teacherId, subject, section, schoolYear
```

`employeeInfo` is a field addition to the existing `users` collection, not
a new collection.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `admin_usecases_test.dart` | employee/assignment field validation |
| Rules | `admin-portal.rules.test.ts` | teacher assignment role gate, employeeInfo editable but status field protected |
| Pure | `provisioning.test.ts` | who may create an account and for which role: the Admin creates every role including another Admin, the Owner creates only the first Director and Admin, a Registrar cannot promote itself, and `owner` is refused for its own reason |
| Emulator | `auditTrail.test.ts` | the trigger names the actor on a create, an edit and a hard delete; keeps both sides of an edit; records that a conversation changed without recording what was said, and says it withheld it; still copies an ordinary record in full; says nothing about its own writes |
| Rules | `oversight-roles.rules.test.ts` | the trail is read whole by the Director and the Admin, only own-actions by a Principal, not at all by the Owner, and written by nobody from a client |

## Deferred to later modules

- **Inventory** (Consumables/Non-consumables, Borrowing/Returns, Stock
  Monitoring, Purchase Requests) — large enough to warrant its own module,
  per the original spec's separate top-level Inventory section.
- **Schedules** (day/time/room class schedule grid) — Teacher Assignment
  answers "who teaches what," Schedules answers "when and where," which is
  a meaningfully different data model (recurring time-block conflicts) best
  tackled as its own unit of work.
- **Monthly Reports** — Reports module.
- **Employee Files** (documents/certificates) — Documents module.

## Signatures on ID cards

School Branding takes a scanned signature for the Principal and for the
Director, alongside their names. Upload one and it prints above that name
on **every** ID card the school issues, students and employees alike —
which is the point: nobody signs cards one at a time.

Signatures are separate fields from the names, not a replacement for
them. A signature nobody can read still needs a printed name under it,
and a school that has entered the names but not scanned the signatures
should still get usable cards with a blank line to sign by hand.

That blank line is why the signature sits in a fixed-height box on the
card whether or not there is an image to draw. Collapsing the space when
a school has not uploaded a scan would shift the name and rule upward and
print a visibly different card from the school next door, and the empty
box is exactly the room somebody needs to sign in.

The upload path is shared with the logo (`_pickAndUpload`), and the
ordering is load-bearing in the same way: the bytes go to Storage first,
and only a successful upload is written to the branding document. Saving
the URL first would point every printed ID at a file that does not exist.

Because the Save button sends only the text fields, the branding write is
a merge — a non-merging write would silently strip both scans off every
future card. There is a test pinning that.

The preview panel behind a signature is white whatever the app theme is:
a scanned signature is black ink on paper, and on a dark panel in dark
mode it is invisible.

## Emergency numbers

The PNP, the fire station, the clinic, the national hotline — the numbers
a school prints on a poster by the door. Admin, Director and Principal
can add, edit, delete and reorder them; `firestore.rules` names exactly
those three roles, and the screen's own editor list matches, so no button
is offered that the rules would then refuse.

Editing was always permitted for those roles. What was missing was a way
to *find* it: the screen was reachable only from Profile, which is where
somebody looks for their own settings, not for a list the whole school
depends on. It now has a tile on all three of those dashboards. A number
that is wrong because nobody could find the screen to fix it is the same
as no number at all.

It stays one screen for everybody rather than an admin-only copy, so the
list a student sees during a fire cannot drift from the list an admin
maintains. Reading is unscoped for the same reason — a number a student
cannot reach is not a safety feature — and nothing in the collection is
personal data.

## Inventory, no longer deferred

This document said Inventory was explicitly deferred, and it was, for
three modules. It exists now: [Module 36](36-inventory.md). The stock
room, the movement log that the quantity on every item is derived from,
and the reorder list — reachable from the Admin dashboard and from
Staff's, next to the material requests it supplies.

## Employee mobile numbers

`EmployeeSummary` carried an email and no phone, so `users/{uid}.phone`
was never set for staff either — which meant password reset by phone
could not work for a teacher any more than it could for a student, and
the office had no number to ring on a morning a class had nobody in front
of it.

Optional and validated, the same rule as the student record: an account
works without a number, it just cannot be recovered by phone. The New
Employee form asks for it, the employee detail screen shows it (and says
plainly when it is missing), and the import gained a **Mobile Number**
column that refuses a row rather than half-importing it.

One thing worth knowing about the demo repository: `updateEmployeeInfo`
and `setUserStatus` rebuild the whole `EmployeeSummary` rather than
copying it, so a field left off either is a field an ordinary HR edit
silently erases. Both carry `phone` through explicitly now.
