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
