# Retention schedule

How long `[SCHOOL NAME]` keeps each kind of record, and why.

> **Draft.** The periods marked `[LIKE THIS]` are the School's decision
> and should be checked against its own regulatory obligations and its
> accountant's advice. What is not a decision is the *shape* of the
> table: keeping a record with no stated period is the finding an audit
> starts with.

---

| Record | Kept for | Why |
|---|---|---|
| Academic records: marks, transcripts, Form 137 | **Permanently** | A graduate asking for a transcript twenty years later is the point of them |
| Enrolment records: name, student number, dates, status | **Permanently** | Needed to say who attended and when |
| Financial records: assessments, payments, receipts, refunds | `[10 years]` | `[Accounting and tax retention]` |
| Attendance records | `[5 years]` after the school year | Supports the academic record and any dispute about it |
| Guidance records | `[5 years]` after the student leaves, then reviewed | Sensitive; kept only while there is a reason to |
| Emergency alerts | `[2 years]` | Incident review and pattern-spotting |
| Coursework and submitted files | `[1 year]` after the school year | The mark is the record that lasts, not the file |
| Document release log (who was handed a transcript) | `[5 years]` | Shows who received a copy of a record |
| Audit trail | `[3 years]` | Traces a change to the person who made it |
| Push notification device tokens | Until sign-out | Removed automatically when a user signs out |
| Data subject requests and their outcomes | `[3 years]` | Evidence of how the school handled them |
| Employee records | `[As required by labour regulations]` | `[HR obligation]` |

## Deletion is not automatic

Nothing in this system deletes records on a timer, and that is
deliberate. An automatic purge that runs against a school's live records
is a much worse failure than a record kept too long — a school that
loses a transcript cannot get it back, and the student is the one who
pays.

Enforcing this schedule is a periodic review by the School, not a
scheduled job. `[Name the person responsible and the review interval.]`

## Deletion when a school leaves

On termination the operator returns or deletes the School's data within
`[30]` days at the School's election, with backups purged within `[90]`.
See the Data Processing Agreement, Section 9.
