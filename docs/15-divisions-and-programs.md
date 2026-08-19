# Module 15: Divisions, College Programs, and Data Isolation

## Overview

A single school (tenant) can run Elementary, High School, and College
under one roof — very common for PH private schools. This module makes
that explicit in the data model (every student declares a division at
registration, college students declare a program/course) and, more
importantly, makes it enforceable: staff can now be scoped to a division
(and, for College, a department) so that data genuinely cannot leak
across them — not just hidden in the UI, but denied by
`firestore.rules`.

## What changed

**Sign-up (Student Registration, Registrar Portal)** — the division
dropdown (Elementary / High School / College) is now a required field.
Selecting College reveals a Program/Course dropdown, populated from
Admin's program catalog, and registration is rejected — client-side
*and* server-side in `registerStudent.ts` — without one selected.

**College Programs (new, Admin Portal)** — a simple catalog
(`programs/{id}`: name, code, department) Director/Admin manage, the same
institutional-configuration pattern as Teacher Assignment.

**Denormalization, not joins** — `registerStudent.ts` looks up the
selected program *once*, at registration, and copies its `department`
onto the student record (`students.department`). Every downstream
security rule (grades, payments, guidanceRecords, summons) can then
division/department-scope access with a single `get()` on the student
doc — never an extra join onto `programs` at read time. Firestore also
caches repeated `get()` calls on the same document path within one rule
evaluation, so this stays cheap even when multiple OR-branches in the
same rule need it.

**Staff scoping (opt-in, backward-compatible)** — `employeeInfo` gained
two optional fields: `assignedDivision`, `assignedDepartment`. **Unset
means unrestricted** — every school, every test, every account that
existed before this module keeps working exactly as it did. Set them
(Admin Portal → Employee Detail, or at creation), and the security rules
actually enforce the restriction for that one account — Registrar,
Faculty, and Guidance are all scopable this way. Director, Admin, and
Owner stay cross-division always; restricting school-wide administrative
roles wasn't asked for and would break legitimate oversight.

## Where the isolation is enforced

| Collection | Scoped role(s) | Behavior |
|---|---|---|
| `students` | registrar, faculty, guidance | read + registrar update |
| `grades` | registrar, faculty, guidance (read); faculty (create/update) | |
| `payments` | registrar | read only (writes are already server-only, Module 8) |
| `guidanceRecords` | guidance | read/create/update |
| `summons` | guidance | read/create/update (student/parent visibility unaffected) |

Self-access (a student reading their own record) and linked-parent access
are **never** division-gated — those checks already resolve to one
specific person regardless of division, so there's nothing to leak.

## Two regressions caught while building this — and how

Both were found by re-reasoning through the *existing* test suite before
shipping, not after:

1. **Missing-field crash on legacy data.** The new rules read
   `resource.data.educationLevel` — but every student fixture seeded by
   *previous* modules' rules tests (Registrar, Student, Parent, Staff/
   Guidance Portal) was written before this field existed, so it's simply
   absent on those documents. Firestore rules throw on direct field
   access to a genuinely missing map key (unlike `.get(key, default)`,
   which is safe). Fixed by switching every such access to
   `.get('educationLevel', 'elementary')` — matching the same default the
   Dart model already uses for pre-existing records — so old data reads
   as "Elementary" rather than erroring the rule out.

2. **Missing-profile-doc crash for the caller.** The new
   `staffEmployeeInfo()` helper originally called `get()` unconditionally
   on the caller's *own* `users/{uid}` doc. Many earlier rules tests
   authenticate a role via custom claims without ever creating that role's
   own Firestore profile document (they only seed the *target* resource
   being tested) — so `get()` would throw, silently failing the branch and
   potentially breaking dozens of already-passing tests. Fixed with an
   `exists()` guard before the `get()`, falling back to `{}`
   (unrestricted) when the caller's own doc isn't found.

Both are covered by `test-rules/division-isolation.rules.test.ts`'s
"unrestricted registrar" test group, which specifically exercises an
account with no `employeeInfo.assignedDivision` set at all.

## Firestore schema additions

```
schools/{schoolId}/students/{id}
  + educationLevel: 'elementary' | 'high_school' | 'college'   (required)
  + programId, programName: string | null                      (college only)
  + department: string | null                                  (denormalized from program)

schools/{schoolId}/users/{uid}.employeeInfo
  + assignedDivision: 'elementary' | 'high_school' | 'college' | null
  + assignedDepartment: string | null

schools/{schoolId}/programs/{id}   -- NEW: name, code, department
```

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `registrar_usecases_test.dart` | college-requires-program, program-only-for-college |
| Domain | `admin_usecases_test.dart` | program name/code/department validation |
| Functions | `educationLevel.test.ts` | validator accepts the 3 levels, rejects everything else |
| Rules | `division-isolation.rules.test.ts` | division-scoped registrar blocked cross-division; unrestricted registrar unaffected; department-scoped faculty blocked cross-department *within* the same division; Director/Admin unaffected |

## Deferred

- **Bulk re-scoping UI** (e.g. "move this whole section to a new
  department") — not needed until a school actually restructures; today's
  per-employee and per-student editing covers the common cases.
- **Division-aware indexes/analytics dashboards** (e.g. Owner revenue
  split by division) — Reports module.
- **Cross-division transfer workflow** (moving a student from High School
  to College) — deliberately not exposed as an ordinary "edit" on Student
  Detail; a real transfer likely wants its own audit trail entry and
  possibly a balance/records handoff, which is a distinct feature from
  this module's scope.
