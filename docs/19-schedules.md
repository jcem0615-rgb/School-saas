# Module 19: Class Schedules

## Overview

The last missing data model. `teacherAssignments` said *who teaches
what*; nothing said *when and where*. Nine features pointed at this gap
and it is the first thing a school asks about in a demo.

A `ScheduleBlock` is one recurring class: subject, section, teacher,
optional room, one weekday, a start and an end.

## One block per weekday

Not one record carrying a set of days. Real timetables are not that tidy
— Mathematics is 7:30 on Monday and 9:15 on Thursday far more often than
it is the same slot all week — and a multi-day record would have to grow
per-day times anyway, which is this with an extra layer.

## Time is two integers

`startMinute` and `endMinute`, minutes from midnight. `TimeOfDay` does
not serialise, a string needs parsing before it can be compared, and a
`Timestamp` would imply a date the record does not have. Minutes sort,
subtract and overlap-test directly, which is the entire arithmetic here.

`parseMinuteOfDay` is deliberately lenient — it takes `7:30 AM`,
`7:30am`, `07:30`, `1330` and `7`. Refusing `730` when the intent is
unmistakable is the kind of strictness that gets a product abandoned.
`formatMinuteOfDay` is hand-rolled rather than going through
`DateFormat`, because there is no date here and inventing one to format a
time is how a timetable ends up an hour out.

## Clash detection is the feature

Three ways a block can collide, and all three are reported at once rather
than the first — an admin who fixes the room only to be told about the
teacher has been made to do the work twice for nothing:

| Clash | Means |
|---|---|
| teacher | One person, two rooms |
| section | One class, two places |
| room | One room, two classes |

Two rules that look like details and are not:

- **Touching ends do not overlap.** A class ending at 9:00 and the next
  starting at 9:00 is how every timetable in the country is written.
  Calling that a clash would make the feature unusable on day one.
- **A blank room is not a room.** Two blocks with no room recorded are in
  no recorded place, not in the same one. Treating them as a clash would
  punish every school that does not timetable rooms.

## Why both writes are callables

`firestore.rules` refuses **every** client write to `scheduleBlocks`.
Clash detection is the whole feature, and a guarantee that lives only in
the UI is not a guarantee — a client that could write directly could book
two classes into one room and the check would be decoration.

The check runs on both sides. The client's copy exists so an admin laying
out a week is told about a clash *before* the round trip, with the
colliding class named while the dialog is still open. The server's copy
is the one that matters.

### The race, stated plainly

`saveScheduleBlock` queries for clashes *before* the write, not inside a
transaction. Firestore transactions cannot query, and the alternative —
reading the whole collection into the transaction to lock it — would
serialise every timetable edit in the school against every other. Two
admins saving colliding classes in the same second can therefore both
succeed.

That is a real race and it is the right trade: timetabling is a
once-a-term activity done by one or two people, the damage is a *visible*
double-booking rather than a silent one, and both blocks stay editable
afterwards. The alternative costs every school a slower editor to guard
against a collision most will never have.

Only the same weekday of the same school year can clash, so that is all
the query reads — a few dozen documents, not the whole week.

## Readable by everybody in the school

`allow read: if belongsToSchool(schoolId)`. A timetable is posted on the
classroom wall. A student needs their own week, a parent needs to know
when their child is in school, and a teacher covering a class needs
somebody else's slot. Scoping it per division would buy nothing and would
stop a student seeing the room their next class is in.

Tenant isolation still applies — another school cannot read it, and
neither can a signed-out visitor.

## A list on screen, a grid on paper

`TimetableView` groups by day, with the time down the left edge. That is
a phone decision: a five-by-ten grid on a 390pt screen either scrolls in
two directions at once or is unreadable. Empty days are dropped — a
school with no Saturday classes should not scroll past an empty Saturday
to reach Friday.

`TimetablePdf` draws the grid, because that is what gets taped to the
classroom door and read by a parent standing in a corridor. Rows are the
distinct start times actually used rather than a fixed hourly ruler: a
school running 7:30, 8:20, 9:10 would get a grid full of empty half-rows
from an hourly one, and a 40-minute homeroom would fall between the
lines.

## Screens

| Screen | Role | What it does |
|---|---|---|
| `ScheduleScreen` | Director / Principal / Admin | The editor, filtered by section, teacher or room |
| `MyTimetableScreen` | Student, Parent, Faculty | One week, read-only, printable |

The editor filters rather than showing the week as one list, because the
questions are always "what does 10-Rizal do", "when is Ms Cruz free",
"is Room 201 taken at ten".

`nextClassToday` returns the class currently under way or the next one,
and null once the day is over — "your next class is on Monday" shown at
four o'clock on a Friday is noise.

## Firestore

```
schools/{schoolId}/scheduleBlocks/{id}   -- tenant-readable; no client writes at all
```

Two composite indexes: `schoolYear + isDeleted + dayOfWeek + startMinute`
for the client's ordered read, and `schoolYear + dayOfWeek + isDeleted`
for the callable's clash query.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `schedule_block_test.dart` | overlap edges, all three clashes, time parsing round-tripped over every minute of the day |
| Functions | `conflicts.test.ts` | the same arithmetic on the copy that is authoritative |
| Demo | `schedule_test.dart` | the seeded week is clash-free; a clash is refused and nothing is written; a block can be moved without clashing with itself |
| Rules | `schedule.rules.test.ts` | seven roles can read, five roles and a student cannot write, nobody can delete |

## Deferred

- **Room as a first-class record.** Rooms are free text, like sections and
  subjects. A room catalogue with capacities would let the editor warn
  that a section of 45 is in a room for 30.
- **Term-specific timetables.** `term` is on the record and nothing reads
  it yet; a school whose second semester differs would want the editor to
  filter on it.
- **Attendance by period.** `markAttendance` knows the day, not the class
  — matching a scan to the block it falls inside is the obvious next use
  of this data.
- **Substitutions.** Marking one occurrence of a block as covered by
  somebody else, without editing the recurring class.
