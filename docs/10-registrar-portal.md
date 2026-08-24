# Module 9b: Registrar/Cashier Portal

## Overview

Covers Student Registration, Student Records/History, and closes a gap
left open since the Payments module: the `students` collection could be
read but never created or edited from the client (`allow write: if false`
placeholder). Payment Collection, Receipts, and Balances are not
rebuilt here — Student Detail links directly into the Payments module's
existing `RecordPaymentScreen`/`PaymentHistoryScreen`, which already
accept a `studentId`.

## Student Registration: why it's a callable, not a client write

Same reasoning as receipt numbers in Payments: `studentNumber` is a
human-readable sequential identifier (`S-2026-000001`) generated via the
same atomic counter transaction pattern (`getNextSequence`), which a
client cannot safely replicate without risking collisions under
concurrent registrations. `registerStudent.ts` also initializes `balance:
0` and `status: 'enrolled'` in the same write, so a student record is
never observably in a half-initialized state.

## Editing an existing record: real client writes, real field boundary

Unlike creation, *editing* an existing student (name, grade, section,
status, guardian contacts) is a direct client Firestore write — same
pattern as Announcements/Meetings/Expenses. The `students` rule now
explicitly protects three fields from that direct-write path even though
Registrar/Admin/Director can edit everything else:

- **`balance`** — only `recordPayment`/`recordRefund` (Payments module)
  may change it, inside the same transaction that writes the payment record.
- **`studentNumber`** — permanent identifier once assigned.
- **`userId`** — only set by `provisionUser.ts`'s validated linking step
  (see below); a direct client write here could silently attach a
  student's academic record to the wrong portal account.

See `test-rules/registrar-portal.rules.test.ts` for tests pinning down
exactly this boundary — editable fields succeed, protected fields fail,
even for a Registrar who can otherwise edit the record.

## Student Portal account provisioning

`provisionUser.ts` (Module 4) is extended two ways this module:

1. **`registrar` added to `PROVISIONING_MATRIX`**, permitted to create
   `student` and `parent` role accounts (previously no caller role could
   create either).
2. **Optional linking fields**: `linkedStudentId` (role `student`) links
   the new account to an existing academic record by setting that
   record's `userId` — validated *before* the Auth account is minted (a
   student record that's already linked, or doesn't exist, fails cleanly
   rather than leaving an orphaned Auth account behind). `linkedStudentIds`
   (role `parent`) is deferred to the Parent Portal module to actually use,
   but the plumbing — validating every referenced student record exists —
   is already here.

A student record does **not** require a portal account to exist — this
is why Student Registration and account provisioning are two separate
actions in the UI (Student Detail shows a "Create Student Portal Account"
button only when `userId` is still null). Younger students or schools
that don't want to issue every student a login can register students
purely as academic/billing records.

## Firestore collections

No new collections — this module fills in `students` (already schema'd
since Module 3, read-gated since Payments) with real create/update rules,
and reuses `payments`/`attendance` via cross-links from Student Detail.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `registrar_usecases_test.dart` | registration field validation, account email validation |
| Functions | `studentNumber.test.ts` | sequential number formatting |
| Rules | `registrar-portal.rules.test.ts` | server-only creation, editable-vs-protected field boundary, faculty has no write access |

## Deferred to later modules

- **TOR, Form 137, printable Student IDs** — require PDF generation
  (Documents module). The *digital* Student ID (QR code) already works
  today via the existing `MyQrIdScreen` once a student has a portal account.
- **Student History** as a dedicated audit-style timeline view — the
  underlying data already exists (generic audit trigger logs every
  `students` doc change); a per-student filtered view of `AuditTrailScreen`
  is a small addition once the Audit Trail module gets its dedicated pass.
- **Reports** (enrollment reports, etc.) — Reports module.
- **Parent account linking UI** — the `linkedStudentIds` validation exists
  in `provisionUser.ts` now, but the Registrar-facing "create a Parent
  account and link these children" screen is built alongside Parent Portal.

## The student list is paged

The list used to read the whole `students` collection on open. That is
fine for the demo's nine records and indefensible for a school with
three thousand: the same three thousand reads every time anybody opens
the screen, on the largest collection in the tenant, from the screen the
registrar's office leaves open all day.

It now asks for twenty at a time, with **Load more** under the last row.

Two details in that are load-bearing:

**The division chips filter the query, not the page.** The `where` goes
to Firestore alongside `isDeleted` — the composite index for
`educationLevel + isDeleted + lastName` already existed. Filtering the
page after it arrived would quietly shrink it: ask for twenty, get the
four Senior High students who happened to fall inside those twenty.

**Search leaves paging behind on purpose.** Firestore cannot match a
substring, so `cruz` can only be found by looking at every record.
Typing switches the screen to the unbounded query and filters it here,
exactly as it did before. Browsing is paged; searching is a deliberate
full read, and it happens when someone asks for it rather than every
time the screen opens.

The alternative — a `startAfter` cursor — is the textbook answer and the
wrong one here. The list is live: a student registered at the next desk
appears without a refresh. A cursor chain means one stream per page,
each with its own lifetime, all needing to stay in sync. One widening
`limit` stays one stream. It costs re-reading page one when you ask for
page two; at twenty a page that is a far better trade than the three
thousand it replaced.

Export is deliberately *not* paged. `fetchAllStudents()` is a separate
one-shot read of the whole roster, because a CSV that silently stopped
at the twenty rows on screen is the exact failure paging invites — and
the kind only noticed after the file has gone to the division office.

Demo mode overrides the page size down to four (`studentPageSizeProvider`).
Nine seeded students would never reach a page of twenty, and paging that
never triggers is paging nobody can check.

## Bulk import, and why it is allowed now

Import used to be refused on this screen, and the reason given was that
`studentNumber`, `userId` and `balance` are server-owned and
`firestore.rules` rejects client writes to them.

That was right about the fields and wrong about the conclusion. The
import does not have to write those fields, because it does not write
documents at all: every row goes through `registerStudent`, the same
callable the New Student form uses. The student number comes from the
same atomic counter, the balance is initialised the same way, and the
same rules apply. Three hundred rows take the path one typed student
takes.

So the checks in `StudentImport` (`presentation/import/student_import.dart`)
mirror the form's, deliberately — an import that could create records the
form would refuse is just a side door for bad data. It is a separate file
from the screen for the same reason: this is where an import is right or
wrong, and it has to be testable without building a widget.

What it refuses:

- a row missing a first or last name, grade level, section or birthday
- a division it does not recognise (it accepts `Senior High School`,
  `senior_high`, `SHS` and `senior high` — but not a guess)
- a strand or program that is not in the catalogue, **or belongs to a
  different division** — the registration form filters that dropdown by
  division and the importer enforces the same thing rather than trusting
  the file
- a birthday it cannot read, one in the future, and `2/31` — which
  `DateTime` would otherwise roll silently into 3 March, filing a student
  under a birthday nobody typed
- a student already enrolled, matched on name *and* birthday, and the
  same student appearing twice in one file

Nothing is applied while any row is bad. A partial import of a
spreadsheet is far harder to unpick than fixing the file and retrying.
When rows do apply they are counted as they land, so a failure partway
through reports what actually happened rather than claiming the file
imported.

## .xlsx, not CSV

Export writes a real workbook (`core/data_transfer/workbook.dart`), which
Excel, WPS Office and Google Sheets all open natively. CSV is still
offered underneath it.

CSV is the wrong default for a roster because Excel and WPS both treat it
as a suggestion. `2024-00001` becomes a date. `09171234567` loses its
leading zero. An enye survives or does not depending on the machine's
regional setting. A registrar exporting a file, mailing it to the
division office and having the student numbers arrive mangled is not
hypothetical — it is the normal outcome. Every cell is written as text
for exactly that reason: a student number is an identifier that happens
to be made of digits, not a quantity. (The CSV export now carries a UTF-8
BOM, which is what stops the enye problem there.)

Import accepts `.xlsx` and `.csv`. Columns are matched **by name**, so
extra columns are ignored and order does not matter. That is what lets a
file exported here be imported straight back somewhere else: the export
carries Student Number, Status and Balance, which the importer has no use
for, and a positional check would reject the app's own output. It also
survives someone sorting the sheet by surname first.

Export and import therefore have different column lists — `headers` and
`importHeaders` on the shared sheet. An export shows everything a record
has; an import can only offer the fields a person is allowed to set, and
asking someone to fill in a Student Number column that will be ignored
invites exactly the assumption that it will not be.

The save path is `FilePicker.saveFile`, not `Printing.sharePdf` as it was:
the latter labels every blob `application/pdf` whatever is in it, so a
workbook arrived as a PDF that Excel had to be argued into opening and
Android's share sheet offered it to PDF readers.
