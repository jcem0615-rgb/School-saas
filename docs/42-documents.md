# Module 42: The student folder

## What this is

The papers a school holds about one child: what the family handed in at
enrolment, what the previous school sent over, and a copy of everything
this school has issued since.

Every registrar's office already has one, in a filing cabinet. The two
questions asked of it are always the same:

* **Do we have their Form 137 yet?** — asked in October, about a transferee,
  usually by somebody who needs an answer before the end of the call.
* **What exactly did we give them in March?** — asked by a receiving school,
  a division office, or a parent who says they never got it.

[Module 10](10-registrar-portal.md) already answered the second question
halfway. `documentReleases` is an append-only log of every document handed
over the counter: when, to whom, how many copies, and why. What it could
not do was show the document. A school could say a Form 137 left the
office on the 3rd and could not produce what was on it.

This module is the other half. The log says a document left; the folder
says what the document was.

## The join

A release and its copy are one act, so they are written as one act.

`recordDocumentRelease` now returns the id of the release it wrote, and
the release screen files the printed PDF straight into the folder with
that id on it. The bytes are built once and used for both the print job
and the copy — not rendered twice — so the page in the folder is the page
that came out of the printer. Two renders either side of midnight would
carry different issue dates, which is exactly the discrepancy a dispute
turns on.

The order is deliberate, and it is the same argument as the one in
[Module 10](10-registrar-portal.md) about logging before printing:

1. **Write the release.** This is the thing the school is answerable for.
2. **Build and print.** The registrar is standing at the counter waiting.
3. **File the copy.** Best effort.

If step 3 fails, the release stands and the screen says the copy could not
be filed. Rolling back a record of something that physically happened —
a document was handed to a parent — because an upload failed would be the
wrong trade in the other direction.

A **reprint** files nothing. It is the same release and the copy is already
there; a second would make the folder claim the school issued it twice.

## Withdrawing, never deleting

`allow delete: if false`, for everyone, the Director included.

A paper leaves the folder by being **archived with a reason**, and the
reason is required — four characters minimum, which lets "wrong student"
through and stops a stabbed keyboard. An archive with no reason is a
delete with extra steps: six months later nobody can say whether the birth
certificate was superseded by a corrected one or removed because somebody
filed it under the wrong child.

The rule holds the update to exactly three fields —
`archivedAt`, `archivedByName`, `archiveReason` — and refuses a second
archive, because the second would overwrite the first reason, which is the
only record of why the paper went. Everything else about the row (which
student, which file, when it was filed) is what makes it evidence, so none
of it can be edited at all.

Archived rows are hidden on the screen until asked for. They are history,
and a folder that opens on everything it ever held buries what it holds
now.

## Who sees it

| Role | Read | File | Withdraw |
|---|---|---|---|
| Director, Admin | any student | yes | yes |
| Principal | within their division | no | no |
| Registrar | within their division | yes | yes |
| Student | their own folder | no | no |
| Parent | their linked children | no | no |
| Faculty, Staff, Guidance | no | no | no |

Two of these are worth saying out loud.

**Faculty are kept out entirely.** A teacher has no reason to browse a
child's civil-registry documents, and "they would not think to" is not a
boundary. There is no screen for it and no rule that would allow it.

**The family can see their own.** A parent who cannot see which of their
child's papers the school holds has to phone up and ask, which is the call
this is meant to stop. They see it read-only — filing and withdrawing stay
with the office, and `firestore.rules` says so independently of the
`readOnly` flag on the screen.

## Medical records are not here

Deliberately. A child's health information is a different sensitivity
class from their Form 137: the registrar's office is the wrong audience
for it, and the list above is the wrong access table. It belongs with
Guidance, behind Guidance's own rules
([Module 14](14-staff-guidance-portals.md)).

## What a Storage rule can and cannot do

This matters and it is easy to get wrong, so it is written down here and
in `storage.rules` itself.

`getDownloadURL()` returns a URL that carries its own access token. **That
URL opens the file for anyone holding it, rules or no rules.** Storage
rules govern who can reach a *path* directly; they are not what keeps a
birth certificate private.

What keeps it private is `firestore.rules`. The URL is a field on a
`studentDocuments` row, and only the office, the student and their parents
can read the row. Widening that read rule widens access to the files
themselves — that is the line to be careful about, not the Storage one.

The Storage rules still earn their place: they stop a signed-in member of
staff browsing the bucket by path, and they are the thing that would
contain a leaked path. `student-documents` is written by Registrar and
Admin only and read by the office only.

While adding that folder, the single wildcard rule that used to cover
everything under `schools/{schoolId}/**` was split into one match per
`UploadFolder`. It had made a school logo and a child's birth certificate
readable by exactly the same people — any signed-in member of the school.
Two others were tightened on the way past:

* `expense-receipts` — Director and Admin. An auditor's paper trail is not
  general reading for the staff room.
* `payment-receipts` — whoever uploaded it, plus Registrar, Admin and
  Director. A photo of a family's bank transfer is their business.

Coursework, branding, the payment QR, student photos and signatures stay
school-wide, which is what they were already and what they are for.

The catch-all is now closed rather than open: a new `UploadFolder` value
has to be given a rule before it works. That is the failure mode that gets
noticed.

## Where it lives

```
app/lib/features/documents/
  domain/entities/student_document.dart     DocumentKind, DocumentOrigin,
                                            StudentDocument, FolderSummary
  domain/repositories/documents_repository.dart
  domain/usecases/document_usecases.dart    watch / file / archive
  data/...                                  model, datasource, impl
  presentation/controllers/                 providers + the action controller
  presentation/screens/student_documents_screen.dart
```

Firestore: `schools/{schoolId}/studentDocuments`, one collection rather
than a subcollection under each student, so a single query can answer
"whose Form 137 is still missing" across a section.

Storage: `schools/{schoolId}/student-documents/{uid}/`.

Reached from the Registrar's student detail screen (**Documents**), the
Student dashboard (**My Documents**) and the Parent's child detail screen
(**Documents**).

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `test/unit/features/documents/student_document_test.dart` | accepted content types, a blank title falling back to the kind, a row with no file or zero bytes refused, an issued copy without a release refused, the archive reason required and trimmed, the summary counting only what is on file |
| Store + screen | `test/smoke/student_documents_test.dart` | filing lands in the folder with the filer stamped from the session, an unsupported type never uploaded, an issued copy pinned to its release, archiving keeps the row and the file, an empty reason refused, withdrawn rows hidden until asked for, the family's view has no filing button |
| Rules | `test-rules/student-documents.rules.test.ts` | the filer cannot be somebody else, faculty and parents cannot file, division scoping on both read and write, the student and their linked parent can read, an unlinked parent cannot, the archive diff held to three fields, a second archive refused, nobody can delete |
| Release | `test/smoke/document_release_test.dart` | the release now returns its id, so the copy can be pinned to it |
