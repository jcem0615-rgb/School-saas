# 39. Oversight and operations

## Overview

Director and Principal supervise. Admin operates.

Before this, the Director could do almost everything an Admin could and
a little more, and the Principal could do a division's worth of the same.
The hierarchy said "Director above Admin" and the permissions said
"Director *and* Admin", which are different claims. This module makes the
second one match the first: the two oversight roles read what they are
entitled to and change almost nothing, and the Admin holds every
operational write in the school.

The change is deliberate about one thing above all: **reads are
untouched**. Taking the buttons away is the point; taking the visibility
away would defeat it, because a supervisor who cannot see the records
cannot supervise. A Director still opens the payroll, the fee schedule,
the stock room and the expense ledger — and finds nothing on them to
press.

## What moved

| | Before | Now |
|---|---|---|
| Branding, school settings | Director, Admin | Admin |
| Another person's profile | Director, Admin | Admin |
| Account status (suspend / activate) | Director, Admin | Admin — and the **Owner** for a Director or Principal |
| Password reset for staff | Owner, Director, Admin | Owner, Admin |
| Creating accounts | Owner, Director, Admin, Registrar | Owner, Admin, Registrar |
| Students: register, edit, balance, parent links | Director, Admin, Registrar | Admin, Registrar |
| Admissions: enquiry through enrolment | Director, Admin, Registrar | Admin, Registrar |
| Payments, refunds, assessments, voids | Director, Admin, Registrar | Admin, Registrar |
| Fee schedules, receipt booklets | Director, Admin | Admin |
| Payroll: rates and running it | Director, Admin | Admin |
| Expenses | Director, Admin | Admin |
| Inventory | Director, Admin, Staff | Admin, Staff |
| Programs | Director, Admin | Admin |
| Timetable | Director, Principal, Admin | Admin |
| Teacher assignments | Director, Principal, Admin | Admin |
| Grades, coursework, answer keys, marking | Director, Admin, Faculty | Admin, Faculty |
| Class registers (cover teaching) | Director, Principal, Admin | Admin |
| Guidance records, summons | Director, Guidance | Admin, Guidance |
| Document releases (TOR, Form 137) | Director, Admin, Registrar | Admin, Registrar |
| Emergency numbers | Director, Principal, Admin | Admin |
| Year-end rollover | Director, Admin, Registrar | Admin, Registrar |
| Data-subject requests | Director, Admin, Registrar | Admin, Registrar |

## What they keep

Four things, and each is a decision rather than data entry.

**Approvals.** Deciding a request is the whole reason the role exists in
that queue. Handing it to the Admin alone would mean an Admin deciding
requests they filed themselves, which is not an approval.

**Leave decisions.** The same argument, for the same reason: an office
that can only approve its own leave is not an approval step either.

**Announcements.** Saying something to the school, under their own name.
Authorship is pinned on create *and* update, so a notice stays their
words — see `docs/06-director-portal.md`.

**Meetings and emergency handling.** Calling a meeting is a claim on
people's time, not a change to a record. Acknowledging an emergency alert
is somebody in charge saying "I am on it", and the first person to say it
is the one recorded.

## Two consequences worth stating rather than discovering

**A school cannot mint its own replacement Admin.** The Director used to
create accounts, including the Admin's. They no longer do, so if a
school's Admin leaves or is locked out, the Owner creates the
replacement. That is the cost of a Director not being able to hand
themselves an operator, and it was chosen with the trade in view.

**Only the Owner can suspend a Director or a Principal.** The rule that
an Admin must not be able to lock out the person supervising them was
already there; it matters more now, because the Director can no longer
suspend the Admin in return. With the Director out of the
account-status callable, "only a Director may" would have meant nobody
in the school could ever deactivate a departed Principal — so
`setUserStatus` gained an Owner path instead. Without that, this change
would have created a lock-out where none existed.

## How it is enforced, in three places

1. **`firestore.rules`** — neither role appears in an operational write
   rule. The note at the top of that file is the authoritative statement
   of the model.
2. **The callables** — the same roles removed from every
   `ALLOWED_ROLES`. Rules cannot police a callable, so this is a separate
   surface that has to agree.
3. **The app** — `UserRole.isOversightOnly` and the `canOperateProvider`
   it feeds. This is a UX boundary, not a security one: the server
   refuses the write either way. What it buys is that a supervisor is
   never handed a form to fill in that the server then rejects, which
   this codebase already treats as worse than no button at all.

## Covered by tests

| Layer | File | Covers |
|---|---|---|
| Rules | `oversight-roles.rules.test.ts` | every operational collection refused to both roles, the admin able to edit each one, the reads still open, and all four kept acts working |
| Rules | the module suites | the same boundary from each collection's own side — a director who cannot publish a fee schedule, keep stock, register a booklet or set a rate |
| Functions | the emulator suites | the callables refusing both roles: payroll, refunds, marking, stock, parent links |
| App | `oversight_roles_test.dart` | no add button for either role on six screens, the admin's still there, the kept acts still offered, and the role model itself |

The app-side test asserts both directions on every screen. One that only
checked the button was absent would pass just as well if the screen
failed to render at all.

## Deferred

- **A read-only affordance rather than an absent one.** A Director
  opening the fee schedules sees the list and no button. A short line
  saying *why* — "the Admin maintains this" — would be kinder than
  silence, and would stop somebody hunting for a control that was
  deliberately removed.
- **Delegation.** A school where the Director genuinely is the Admin (a
  small school with three staff) now needs two accounts. Letting the
  Owner mark a school "single-operator" and grant the Director the Admin
  role as well would fit, and is a school-shaped decision rather than a
  code one.
