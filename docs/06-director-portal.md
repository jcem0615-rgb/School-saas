# Module 6: Director Portal

## Overview

Director Portal covers Dashboard, Announcements, Meeting Scheduler,
Approvals, and Expenses. Attendance Monitoring, Payments, Reports, and
Analytics deep-dives are intentionally **not** duplicated here — the
Dashboard reads live aggregates from the `attendance` and `payments`
collections (defined in Module 3's schema), but the screens that *produce*
that data belong to the QR Attendance and Payments modules, built next.

## Architecture decision: the generic audit trigger

Auth and Owner Portal both needed bespoke Cloud Functions because they had
real server-side business logic (claims, billing math). Director Portal's
four CRUD screens don't — an announcement is just a document. Requiring a
callable function for every simple create/update across the whole app
would be a lot of near-identical boilerplate for zero benefit.

Instead, this module introduces `onAnyTenantDocWrite`
(`functions/src/triggers/audit/onAnyTenantDocWrite.ts`): a single Firestore
trigger on `schools/{schoolId}/{collectionId}/{docId}` that fires on *any*
write to *any* direct tenant subcollection (except a short exclusion list)
and automatically writes the corresponding audit log entry — diffing
before/after state and classifying it as create/update/delete/soft_delete/
restore via the pure `classifyAction()` function.

This means: Announcements, Meetings, Approvals, and Expenses (and every
future CRUD-only module) get full audit coverage for free, simply by
writing directly to Firestore from the client under rules that check role
+ tenant + field-level constraints. Callables remain reserved for actions
with actual server logic to run.

## Firestore collections added

```
schools/{schoolId}/announcements/{id}   -- title, body, audience, pinned
schools/{schoolId}/meetings/{id}        -- title, start/end, location, attendeeRoles, status
schools/{schoolId}/approvals/{id}       -- type, title, requestedByRole, status, decision fields
schools/{schoolId}/expenses/{id}        -- category, description, amount, date
```

`approvals` is deliberately generic (a `type` field, not a separate
collection per request kind) so future modules — Staff material requests,
Inventory purchase requests — write into the same collection and appear in
the Director's one inbox, rather than needing N different approval UIs.

## Security Model additions this module

- **Asymmetric create/update on `approvals`**: any active tenant member
  can *file* a request (`create`), but only Director/Admin can *decide*
  it (`update`, and only from `pending` to `approved`/`rejected`). A rule
  also checks `request.resource.data.requestedByRole == claims().role` so
  a Staff account can't file a request claiming to be a Director.
- **Expenses are financial data**: readable only by
  `owner/director/admin/registrar`, not the whole tenant the way
  Announcements/Meetings are.
- **Immutable authorship**: update rules on announcements/meetings/expenses
  require `request.resource.data.createdBy == resource.data.createdBy` —
  editing content is fine, silently reassigning who created it is not.
- See `test-rules/director-portal.rules.test.ts`.

## Dashboard aggregates: why no rollup document

The Owner's platform-wide revenue summary needs a maintained rollup
because summing across potentially hundreds of schools on-demand would be
slow. A single school's *today* numbers are cheap: `fetchDashboardAggregates()`
uses Firestore's native `count()` and `sum()` aggregation queries directly,
computed on demand (pull-to-refresh, or on screen entry) rather than
streamed — Directors expect this screen to reflect the current moment
when they open it, not eventual consistency from a scheduled job.

## The approval history

A decided request used to show its outcome and the remarks, and nothing
else. The one question anybody asks about an approval weeks later --
"who approved this?" -- had no answer on the screen that recorded it.

A decision now carries `decidedByUid`, `decidedByName`, `decidedByRole`
and `decidedAt`, and the card renders all four alongside the reason.

`decidedByUid` is the one that matters, because `firestore.rules` pins it
to `request.auth.uid` and `decidedByRole` to the caller's own claim. The
same shape as the authorship check already on create: without it a
decider could write any name beside their decision, and a history that
can be authored is not a history.

The request's `details` are rendered too, whatever they are. That map is
deliberately free-form -- a material request and a promissory note file
into the same collection -- so the card lays out whatever keys it finds
rather than knowing about either. A director approving on a title alone
has no idea what quantity or amount they just agreed to, and afterwards
neither does anybody reading the record.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `director_usecases_test.dart` | announcement/meeting/approval/expense validation |
| Rules | `director-portal.rules.test.ts` | approval role asymmetry, self-decision block, expense visibility |
| Functions | `classifyAction.test.ts` | audit action classification (create/update/delete/soft_delete/restore) |

## Deferred to later modules

- Attendance Monitoring detail views (QR Attendance module — next)
- Payments detail views (Payments module)
- Director-side Reports/Analytics exports (Reports module)
- Director's own audit trail search UI (Audit Trail module — data already
  flowing in via the generic trigger)

## Importing expenses

Recorded By exports but does not import. It names who entered the
spending, the datasource stamps it from the signed-in user, and a column
that let a file claim otherwise would put someone else's name against
money they never recorded. An imported expense is therefore recorded
under whoever uploaded the file, which is the honest reading — they are
the one putting it in the ledger.

Categories are matched against the catalogue rather than taken as typed.
A free category column looks harmless until "Utilties" becomes its own
line in the expense report, splitting a figure the Director is reading as
a total.

A row whose date, category, description and amount all match one already
in the ledger is refused. That is what a file imported twice looks like,
and doubling a month of spending is both easy to do and hard to notice
afterwards. Two genuinely identical expenses on one day do happen; saying
which is which in the description is the way through, and is worth more
in the ledger than a bare duplicate anyway.

Amounts are read the way a spreadsheet writes them — "₱1,250.00",
"1 250", "(250.00)" — because refusing those sends someone back to retype
a column that was never wrong. Zero and negative amounts are refused: a
refund is its own record, not a negative expense.
