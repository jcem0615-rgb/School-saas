# 22. Emergency

## Overview

Two collections and one button. `emergencyContacts` is the list of
numbers a school would otherwise print on a poster by the door;
`emergencyAlerts` is what exists after a student presses the button on
their own phone.

This module has the least forgiving failure mode in the app, and the
whole design follows from that: the alert is a **document** first and a
notification second, and the set of people told is resolved on the
server from records the student cannot edit.

## Why the alert is a record, not just a push

Push depends on notification permission, a registered service worker, a
configured Firebase project and a phone that is on. Any of those can be
missing on the day it matters. So the alert is a document that staff can
see on their Emergency Alerts screen regardless, and that is still there
afterwards as a record of what was raised and when.

The same argument runs the other way for the family: `ParentAlertsScreen`
exists so a parent who heard nothing and opened the app anyway can find
out, and it carries the school's own numbers on it — somebody who has
just read that their child pressed the button is going to call
somebody, and making them navigate to find the number is the wrong thing
to do to them.

## Where the student was

`latitude`, `longitude` and `locationAccuracyMeters` are captured once,
at the moment the button is pressed. "Send help" is not actionable
without "and here is where I am": a school is a big place and a student
in trouble may not be able to describe where they are.

Three deliberate choices around it:

- **Asking for a location must never delay the alert.** The probe is
  bounded at eight seconds and the deadline is enforced twice — inside
  the probe and again at the call site — because this is the one call in
  the app where a plugin that hangs would leave a student who pressed the
  button watching a spinner. Whichever gives up first, the alert goes.
- **A failure is recorded, not left blank.** `locationFailure` says
  *why* there is no position, so staff can tell "the student declined to
  share" from "nobody ever asked". Without it, an alert with no location
  is ambiguous in exactly the moment when guessing is most expensive.
- **It is where they called from, not a track.** Captured once and never
  updated. Following somebody around a campus after the fact is a
  different and much larger decision.

## Who is told

Resolved server-side in `onEmergencyAlertCreated.ts`, from records the
student cannot edit:

| Who | Why | How they are found |
|---|---|---|
| The section's adviser | Knows the child, usually nearest to them | The advisory assignment for the alert's section |
| Guidance, Director, Principal, Admin | The roles whose job responding is | Their role, every time |
| The child's linked parents | | `linkedStudentIds` on their own user document |

**The adviser used to be the only member of staff told, and was found by
an exact section-name match.** Both halves of that were wrong, and both
failed the same silent way — an alert reaching nobody in the building:

- A section name is typed by hand on the student record and again on the
  teacher's assignment. `where("section", "==", ...)` between
  "Grade 10 - Rizal" and "Grade 10 - rizal " simply found no adviser, and
  said nothing about it. Assignments are now read and matched through
  `shared/sections.ts`, the same normaliser messaging and announcements
  use.
- Even matched correctly, one adviser is one absence, one resignation or
  one unset advisory away from nobody. Guidance and the office are told
  every time now. Every teacher in the school would be the wrong answer;
  nobody is a worse one, and over-telling is the right failure for the
  one notification somebody may be in danger behind.

The alert is the only delivery in the app marked `urgent`, which bypasses
the batching window and rings through.

## Handling one

Acknowledging ("I'm on it") and resolving are separate acts, often by
different people, and **each is written once**. Two staff opening the
list and both tapping Acknowledge used to mean the second write replaced
the first, so the record of who actually responded became whoever tapped
last. `firestore.rules` now refuses a second acknowledgement and a second
resolution; the screen already hid both buttons once used, and this is
what makes that true when two phones disagree.

Everything the student wrote — the message, the location, the time — is
in the immutable set. Handling an alert must not become a route to
editing the report of it, and an alert that can be quietly retracted is
worth less than one that cannot, including when the pressure to retract
comes from somebody else.

## Two rules that break the pattern on purpose

**`emergencyContacts` is readable by every role with no scoping at all.**
A number a student cannot reach during a fire is not a safety feature.
Nothing in that collection is personal data; it is what a school prints
on a poster.

**`emergencyAlerts` has no `schoolIsAccessible()` check on create or
read**, unlike everywhere else in `firestore.rules`. A school whose
subscription has lapsed still has children in it, and billing is not a
reason to drop an emergency alert on the floor.

That carve-out reaches exactly as far as those two rules and no further,
which is worth stating plainly rather than implying:

* the student can still raise one, and staff can still read the list;
* the push and the inbox item are written by the Admin SDK, so they go
  out either way;
* but the notification **inbox** is gated like everything else, and the
  parent's own alerts screen depends on their children list, which is
  also gated. So in a suspended school a parent gets the push and can
  read it on the lock screen, and the in-app routes to it do not work.

Closing that properly means a suspended-school mode in the app rather
than more exceptions in the rules, and it is listed under Deferred.

## Firestore

```
schools/{schoolId}/emergencyContacts/{id}  -- label, phone, notes, sortOrder
schools/{schoolId}/emergencyAlerts/{id}    -- studentId, studentName, section, userId,
                                              message, raisedAt, latitude, longitude,
                                              locationAccuracyMeters, locationFailure,
                                              acknowledged*/resolved* fields
```

One composite index: `emergencyAlerts` on `studentId ASC, raisedAt DESC`.
The per-student query used to be capped at fifty with no ordering at all,
which in Firestore means fifty in document-id order — and the ids are
random, so a family with a long history would have been shown an
arbitrary fifty rather than the recent ones.

## Covered by tests

| Layer | File | Covers |
|---|---|---|
| Functions | `sections/sections.test.ts` | what counts as the same class, which is what finds the adviser |
| Emulator | `emergency-emulator/emergencyFanOut.test.ts` | the adviser found through a differently-typed section, guidance and the office told every time, the school still told when a section has no adviser, the right family and no other, no registrar, no leaver, the wording, and one notification per person however many ways they qualify |
| Rules | `emergency.rules.test.ts` | contacts readable by everyone and editable by the office, an alert raised only as oneself and never backdated, a lapsed school still accepting one, staff-only handling, the first acknowledgement and the first resolution standing, and neither the student nor staff able to rewrite what was said |
| Demo | `emergency_test.dart`, `parent_emergency_test.dart` | the button, the fan-out to adviser/guidance/office/parents, acknowledge-then-resolve, and what a parent sees |

## Deferred

- **A suspended-school mode.** See above: the in-app routes to an alert
  stop working before the alert does. The app has no "your school's
  subscription has lapsed" state, so reads simply fail; giving it one
  would let the emergency screens stay reachable while the rest is held
  back.
- **Deep-linking a notification to the alert.** Every emergency push
  lands on `/notifications`. The Emergency Alerts and Parent Alerts
  screens are pushed from dashboards rather than routed, so there is
  nothing to link to yet — which means the location, the accuracy and the
  map link are one navigation further away than they should be in the one
  flow where that matters.
- **Escalation.** Nothing happens if an alert is not acknowledged. A
  second notification after a few minutes, to a wider set, is the obvious
  next step and is a decision about the school's own procedure rather
  than about this code.
