# Data Processing Agreement

**Between** `[SCHOOL NAME]` ("the School") and `[OPERATOR LEGAL NAME]`
("the Operator"), covering the School's use of the LogicClass school
management system.

> **Draft for review by counsel.** The factual sections — what is
> processed, where it is held, who can reach it — describe the system
> accurately. The contractual terms are ordinary and should still be
> read by a lawyer before signing. Replace everything in `[BRACKETS]`.

---

## 1. Roles

The School is the Personal Information Controller. It decides what
personal information is collected about its students, employees and
their families, and why.

The Operator is the Personal Information Processor. It processes that
information only on the School's documented instructions, which for
ordinary use means the operation of the system itself.

## 2. What is processed

| Category | Data subjects |
|---|---|
| Identity and enrolment records, including photographs | Students, employees |
| Guardian and emergency contact details | Parents and guardians |
| Attendance records, including scan location where the device provides one | Students, employees |
| Academic records: marks, submitted work, transcripts | Students |
| Financial records: assessments, payments, receipts, balances | Students, parents |
| Emergency alerts, including device location where available | Students |
| Guidance records and summonses | Students |
| Account records, device push tokens, and an audit trail of actions | All users |

Some of this is **sensitive personal information** as that term is used
in Philippine law, and some concerns **minors**. Both are processed on
the basis that the School requires them to run a school and to meet its
own reporting obligations, not on the basis of consent alone.

## 3. What the Operator will not do

The Operator will not:

- use the School's data for any purpose of its own, including product
  analytics that identify individuals, marketing, or model training;
- sell, rent or share the data with any third party except the
  sub-processors listed in Section 4;
- retain the data after termination beyond the period in Section 8.

## 4. Sub-processors

| Sub-processor | Purpose | Location |
|---|---|---|
| Google Cloud / Firebase | Database, authentication, file storage, server functions | `[REGION AS CONFIGURED — the functions in this system are deployed to asia-southeast1]` |
| `[HOSTING PROVIDER]` | Serving the web application | `[REGION]` |

The Operator will give the School `[30]` days' notice before adding or
replacing a sub-processor, and the School may object.

## 5. Security

The Operator maintains, at a minimum:

- **Access control enforced at the database, not only in the interface.**
  What each role may read and write is defined in security rules
  evaluated on every request, so a screen a user cannot reach is also
  data they cannot fetch.
- **Server-side control of the records that matter.** Balances, receipts,
  fee assessments, timetable entries and audit entries can only be
  written by server functions, never directly by a device.
- **Tenant isolation.** Each school's records are namespaced and the
  rules refuse cross-school reads. This is covered by an automated test
  suite that runs against the rules themselves.
- **An audit trail** of changes to records, attributable to a user.
- **Encryption** in transit and at rest, as provided by the underlying
  cloud platform.
- **Access on the Operator's side limited to named personnel** who need
  it for support, and only for as long as they need it.

## 6. Personnel

The Operator will ensure that anyone it authorises to process the data
is bound by confidentiality and has been instructed on their obligations.

## 7. Breach notification

The Operator will notify the School's Data Protection Officer **without
undue delay and in any case within `[24]` hours** of becoming aware of a
personal data breach affecting the School's data, with whatever facts are
known at that point, and will update the School as more is established.

The Operator will assist the School with any notification the School must
make to the regulator or to affected individuals. **The School makes
those notifications**, because the School is the Controller.

## 8. Data subject requests

Requests from individuals go to the School, which decides them. The
Operator will assist by:

- providing an export of what the system holds about a named individual;
- carrying out corrections or deletions the School instructs, except
  where doing so would break a record the School is required to keep;
- not answering a data subject directly, but referring them to the
  School.

The system records these requests, what was decided and by whom, so the
School can show its own handling of them.

## 9. Retention and return

On termination, the Operator will, at the School's election, return the
School's data in a machine-readable format or delete it, within `[30]`
days. Backups are purged on their ordinary cycle, within `[90]` days.

The Operator will not delete the School's data during the term without
written instruction.

## 10. Audit

The School may, on `[30]` days' notice and no more than once a year,
request information reasonably necessary to confirm the Operator's
compliance with this agreement.

## 11. Term

This agreement runs for as long as the Operator processes personal
information on the School's behalf, and survives termination of the
service agreement to the extent of Section 9.

---

**School** `[NAME]` `[POSITION]` `[DATE]`

**Operator** `[NAME]` `[POSITION]` `[DATE]`
