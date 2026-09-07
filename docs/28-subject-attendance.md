# Module 28: Per-subject attendance

## Overview

The school already knew whether a student came in through the gate. It
did not know whether they were in Physics.

That is not a small gap. "Did they come to school" is what a truancy
report needs; "were they in the lesson" is what a subject teacher, a
failing grade and a worried parent are all actually asking, and the daily
QR record cannot answer it. A student can scan in at 7:15 and be
somewhere other than their 10:40 class for the rest of the term without
a single record saying so.

So each timetabled class now gets a **session**: the teacher presses
**Time In** at the start, marks the exceptions, and presses **Time Out**
at the end.

## The shape of it

Two collections, not one:

| Collection | One document per | What it is |
| --- | --- | --- |
| `classSessions/{date}_{blockId}` | class, per day | The lesson as it ran: who took it, when it started and finished, how the section came out |
| `subjectAttendance/{sessionId}_{studentId}` | student, per lesson | One line in the register: present/late/absent/excused, with a time in and a time out |

Marks are their own collection rather than an array on the session for
two reasons. A section of forty inside one document caps the class at
whatever fits in a megabyte, and — the real one — "was this child in
Physics all term" is a query *across* sessions. As a subcollection that
needs a collection-group index the marks would otherwise never require;
as a top-level collection with a denormalised `subject`, `section` and
`date`, it is one ordinary query.

Both document ids are derived, not generated, and that is what makes the
whole thing idempotent. `2026-03-03_blk_physics` is *the* session for
that class on that day. Pressing Time In twice is not hypothetical — it
is what happens when the first press is slow and the teacher is holding
a phone in front of a class — and with a generated id that produces two
sessions and two half-filled registers.

## What is built

**Three callables**, in `functions/src/callable/classSessions/`:

* `openClassSession` — Time In. Checks the class is on the timetable
  *today*, builds the register from the section's enrolled students, and
  returns the existing session untouched if one is already open.
* `closeClassSession` — Time Out. Stamps the finish on the session and on
  everyone who was in the room, and writes the counts onto the session.
* `markSubjectAttendance` — one tap on one name.

**The pure parts**, in `functions/src/shared/attendance/classSession.ts`,
with tests: the id derivation, the weekday check, the edit window, the
roll counts, and the duration.

**The app**, in `app/lib/features/class_sessions/`: the teacher's day
(`TodaysClassesScreen`), the register (`ClassRollScreen`), and the
family-facing view (`SubjectAttendanceScreen`), reachable from the
Faculty dashboard, the Student dashboard, and each child on the Parent
portal.

## Deliberate choices

**Everybody starts present.** Marking a register is marking exceptions. A
teacher with forty students and three absences should make three taps,
not forty — and a default of "unmarked" would mean a class that ran to
the bell and was never fully marked recorded *nothing at all* about the
thirty-seven children who were there.

**The register may be corrected today, and not after.** A teacher who
marked the wrong name should fix it there and then. Closing the session
does not end that window: Time Out means "the class is over", not "this
is now history", and a teacher who notices at the door should not have
to ask the office. But a register that stays editable for a term is not a
record of what happened — it is a record of what somebody last thought.
After today it is the registrar's to amend, with the paperwork that
implies.

**The date comes from the school's timezone, server-side.** A class
opened at 7:30 in Manila is 23:30 the previous day in UTC. A date key
taken from the server clock files every early lesson under yesterday,
which is not a rounding error: it is a register saying a child was in two
Physics lessons on Tuesday and none on Wednesday.

**A class not timetabled today cannot be started.** The teacher's screen
lists today's classes, but a screen is not a guarantee — a stale list, or
a phone that slept through midnight, would otherwise file a day's marks
under the wrong date.

**The block's teacher, or the office.** Substitutes exist, and "update
the timetable first" is not a thing anybody does at 7:28 in the morning,
so Director/Principal/Admin can open and close a class too. Who actually
pressed the button is recorded separately from who the timetable says
teaches it, so a covered lesson says so. Students, parents and staff are
absent from that list on purpose — the same one-way boundary the QR
scanner draws, so a compromised student device cannot mark itself
present.

**Nothing writes these collections from a client.** `firestore.rules`
refuses every client write to both. The register is the record a disputed
grade gets argued over, and the callables are the only door.

**An absent student gets no time out.** They had no time in. A duration
against a child who was not in the room is worse than a blank.

**The mark decides the arrival time, not the row.** Opening a session
stamps every student on the roll with the session's own start time. The
mark used to keep whatever was already on the row — which, since the row
had only ever held the bell time, meant a student switched to *late* was
recorded as having arrived on the bell. The comment above that line
promised the opposite. `timeInForMark` now derives it: *present* is the
bell (that is what the mark means), *late* is the moment the teacher
marked them (the only record there is of when they came through the
door), *absent* and *excused* have no arrival at all. Correcting a
mis-tap from late back to present puts the child back on the bell rather
than leaving them permanently recorded as having walked in halfway
through. Clamped at the session start, so a device whose clock runs slow
cannot produce a student who arrived before the class began.

**A roll has an upper bound.** One session document plus one mark per
student, in one batch, and a Firestore batch holds 500 writes. A section
of five hundred is a data problem rather than a class — but without the
check the failure is an opaque Firestore error in front of a teacher
holding a phone, and the office cannot act on that.

**Excused lessons stay in the denominator.** A school that dropped them
would report a child who missed half a term with a note as having a
perfect record, which is not what either the teacher or the parent is
asking.

**The family view is worst subject first.** The reason anybody opens it
is to find the one that is going wrong; alphabetical order makes them
read all eight to find it.

## Who can read what

| | Session | Marks |
| --- | --- | --- |
| The student | no | their own |
| Their parent | no | their child's |
| Faculty, guidance, registrar, admin, principal, director | yes | yes |
| Anybody else | no | no |

A session document is the class — who taught it, how the whole section
came out. A family's business is their own child's line in it.

Marks are division-scoped for the same roles, and for the same reason, as
`grades`: a mark in a lesson is no less about one named child than a mark
in an exam. Director and Admin stay cross-division, as they are
everywhere else. Every row here is built from a section's enrolment, so
the student record it names always exists — which is why this rule can
call `scopeAllowsStudentById` directly, where the gate-attendance one has
to guard first (see `docs/07-qr-attendance.md`).

## Covered by tests

* `functions/test/shared/attendance/classSession.test.ts` — the id
  derivation, Monday-versus-Tuesday, the edit window, an unrecognised
  mark still counting toward the total, and a duration that never goes
  negative when two clocks disagree.
* `test-rules/subject-attendance.rules.test.ts` — who reads what, and
  that no client can write either collection, including the teacher who
  took the class.
* `app/test/smoke/subject_attendance_test.dart` — Time In opening a
  register with everyone present, a second press not replacing it, a
  class not timetabled today being refused, an earlier day's register
  refusing a change, Time Out stamping only the students who were there,
  a correction after Time Out keeping the summary honest, and the
  family's per-subject rates.
* `app/test/smoke/portal_actions_test.dart` — the three screens render.
* `app/test/unit/features/class_sessions/domain/time_in_for_mark_test.dart`
  — the arrival-time arithmetic on the client's copy.
* `functions/test/shared/attendance-emulator/gateAndTimetable.test.ts` —
  `openClassSession` and `markSubjectAttendance` against a real
  Firestore: a latecomer recorded when they were marked rather than on
  the bell, the correction back to present, and an absent student left
  with no arrival.

## Not covered

Time Out is not exercised against the emulator. `openClassSession` and
`markSubjectAttendance` now are, and the rest — the counts recomputed
after a correction on a closed session, the stamp written to every
student who was there — is tested on the pure logic, the rules and the
demo, but "the deployed `closeClassSession` does what the demo does" is
still asserted by reading rather than by running.
