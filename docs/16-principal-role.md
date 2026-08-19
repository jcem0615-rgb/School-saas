# Module 16: Principal Role

## Overview

Adds `principal` as a new role: a **division-level academic leader**
(e.g. "Elementary Principal," "High School Principal," "College Dean"),
distinct from `director` (school-wide) the same way `assignedDivision`
already distinguishes Registrar/Faculty/Guidance from Director/Admin
(Module 15). This is the fifth role to plug into that same
division-isolation system rather than needing its own bespoke one.

## Where Principal sits in the hierarchy

```
Owner (platform-level)
  └─ Director (school-wide)
       ├─ Principal (division-level: Elementary / High School / College)
       ├─ Admin (school-wide operations)
       └─ Registrar / Faculty / Staff / Guidance (operational, division-scopable)
```

Both **Director and Admin can provision a Principal account** (Admin
Portal → Employee Management is the one working provisioning UI in this
build; Director's own equivalent screen doesn't exist yet — see
`docs/10-registrar-portal.md`'s note on this same gap for Registrar-
created accounts). A Principal's own `employeeInfo.assignedDivision`
should almost always be set (that's the entire point of the role), but
it's not hard-required — an unconfigured Principal behaves school-wide,
same as every other role before this module.

## What a Principal can do — and the reasoning for each boundary

| Action | Principal? | Scoped? | Reasoning |
|---|---|---|---|
| Read students | Yes | Yes | Same pattern as Registrar/Faculty/Guidance |
| Edit students | No | - | Records editing stays Registrar's job; Principal is oversight, not data entry |
| Read grades | Yes | Yes | Academic oversight for their division |
| Create/edit grades | No | - | Grading stays Faculty-authored |
| Read guidance records | Yes | Yes | Division-level student welfare oversight |
| Create/edit guidance records | No | - | Counseling notes stay a Guidance Office action |
| Read summons | Yes | Yes | Same reasoning as guidance records |
| Issue/decide summons | No | - | Stays Guidance Office + Director/Admin |
| Read payments | No | - | Financial data stays Director/Admin/Registrar -- deliberate separation of academic and financial duties, same boundary already drawn for `expenses` |
| Create/edit announcements | Yes | No | Leadership communication action |
| Create/edit meetings | Yes | No | Leadership scheduling action |
| Decide approvals | Yes | No | See note below |
| Read/create teacher assignments | Yes | No | Matches existing (already-unscoped) pattern for that collection |
| Read coursework (incl. drafts) | Yes | No | Oversight visibility, not authoring |
| Scan QR attendance | Yes | -- | Added to `SCANNER_ALLOWED_ROLES` |
| Suspend/activate accounts | No | - | Deliberately conservative for this pass -- see below |
| Reset passwords | No | - | Same reasoning |

**Approvals decide-rights are not division-scoped.** Unlike
students/grades/guidanceRecords/summons, the `approvals` collection
doesn't carry a denormalized division/department field — material
requests and promissory notes don't have a natural "which division does
this belong to" the way a student record does. Scoping this properly
would need a larger redesign (denormalizing a division onto every
approval at filing time). Documented here as a deliberate, reasoned
boundary rather than a silent gap: a Principal today can decide *any*
pending request school-wide, same as Director/Admin.

**Account-security actions stay conservative.** `setUserStatus` (User
Approval / activate-suspend) and `resetPasswordAdmin` remain
Director/Admin only in this pass, even though Principal now has real
leadership authority elsewhere. This was a judgment call, not a hard
technical constraint — easy to extend later (add `"principal"` to
`STATUS_ALLOWED_ROLES` / `RESET_ALLOWED_ROLES`) if a school wants
Principals to self-serve this for their own division's staff. What *is*
in place already: a Director's or Principal's account can only have its
status changed by a Director — an Admin cannot suspend either one,
preventing a lower-privilege role from locking out a higher one.

## Why financial data (payments) stays excluded

This mirrors a decision already made for `expenses` in Director Portal
(Module 6): academic leadership and financial operations are kept as
separate concerns. A Principal overseeing student welfare and academics
for their division doesn't need visibility into tuition balances to do
that job, and keeping the boundary consistent (rather than granting
payments access here while denying it elsewhere) makes the security model
easier to reason about as a whole.

## No new collections

This module only adds a role and extends existing rule blocks — no new
Firestore collections, no new Cloud Functions beyond the small edits to
`provisionUser.ts` (provisioning matrix), `setUserStatus.ts` (hierarchy
protection), and `markAttendance.ts` (scanner role list).

## The Principal Portal itself: zero new business logic

`PrincipalDashboardScreen` reuses `AnnouncementsScreen`,
`MeetingsScreen`, `ApprovalsScreen`, `TeacherAssignmentsScreen`, and
`StudentListScreen` directly — no new screens beyond the dashboard
itself. What actually makes a Principal's experience different from
Director's is `firestore.rules`, not different UI code: the exact same
`StudentListScreen` a Principal opens will only ever show them the
students their `scopeAllowsStudent` check permits.

## Testing

| Layer | File | Covers |
|---|---|---|
| Rules | `principal-role.rules.test.ts` | division-scoped read for students/guidanceRecords, cross-division blocked, unrestricted Principal unaffected, read-only on students confirmed, leadership actions (announcements, approval decisions) work, pending-only guard still applies |

## Deferred

- **Principal self-service account-security actions** (suspend/reset
  password for their own division's staff) — noted above, straightforward
  to add later.
- **Division-aware approvals** — would need approvals to carry a
  denormalized division at filing time to make Principal's decide-rights
  properly scoped rather than school-wide.
- **A dedicated "Division Students" read-only view** — Principal currently
  reuses Registrar's `StudentListScreen` as-is (including its Register
  Student button and edit-capable Student Detail screen); any write
  attempt is correctly denied by rules, but the UI doesn't yet hide those
  controls for a role that can't use them. Not a security gap — a UX
  polish item for a future pass.
