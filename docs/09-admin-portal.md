# Module 9a: Admin Portal

## Overview

Covers Employee Management, User Approval, Reset Password, and Teacher
Assignment as new features. Announcements, Attendance Monitoring, and
Audit Trail are wired in as navigation entries into screens already built
in earlier modules (Director Portal, QR Attendance, and a new shared Audit
Trail feature respectively) — Admin's rules already permitted these
actions; this module just gives Admin a front door to them.

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

## Audit Trail (pulled forward as a shared feature)

Built as its own `features/audit_trail/` module (not nested under Admin
Portal) since Director and Owner need the same screen. Filters by module
and date range via Firestore query composition; free-text search over
`userName`/`remarks` is done client-side over the fetched page, since
Firestore has no native substring search — full-text search infrastructure
is a Reports-module concern if usage ever demands it at scale. PDF/Excel
export and restore-from-soft-delete are also deferred to Reports &
Documents.

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

