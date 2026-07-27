# Module 5: Owner Portal & Subscription Billing

## Overview

The Owner Portal is the only part of the app that operates outside tenant
boundaries — it reads/writes `platform_*` collections, never
`schools/{schoolId}/*` directly (billing actions go through Cloud
Functions, which then touch tenant-adjacent platform data).

## Screens delivered this module

- **Owner Dashboard** — daily/monthly/yearly revenue tiles + a "needs
  attention" list of grace-period/suspended schools.
- **School Management (list)** — every school, filterable by status,
  searchable by name.
- **School Detail** — pause/resume action, invoice history for that school.
- **Invoice tiles** — status-colored, part of School Detail (a standalone
  cross-school Invoice list screen is deferred to the Reports module,
  where PDF/Excel export also lives).

## Billing Engine

```
Daily Charge   = Active Enrolled Students × billingRatePerStudent (default ₱3)
Monthly Charge = sum of that school's daily charges within the billing cycle
```

Two scheduled Cloud Functions drive this, both server-only — the client
never computes or writes a charge:

1. **`dailyBillingJob`** (00:05 Asia/Manila) — for every school: counts
   `students` where `status == 'enrolled'`, computes the day's charge,
   appends it to the current month's invoice (creating one on the 1st),
   updates `platform_subscriptions.currentCycleAccrued`, and rewrites the
   single `platform_revenue_summary/current` doc the Owner Dashboard reads.
   Suspended schools are excluded from further accrual.

2. **`gracePeriodCheckJob`** (00:30 Asia/Manila) — flags invoices past
   `dueDate` as `overdue`, starts the grace-period clock on first overdue
   detection, and auto-suspends once `gracePeriodDays` (per-school,
   default 7) elapses. A **manually** paused school
   (`autoSuspendEnabled: false`) is explicitly skipped, so this job can
   never silently undo an Owner's deliberate pause.

## Pause / Resume / Payment — why three separate callables

| Callable | Who | Effect |
|---|---|---|
| `pauseSchool` | Owner only | Immediate suspend, `autoSuspendEnabled: false` (sticky — billing job won't touch it) |
| `resumeSchool` | Owner only | Immediate reactivate, clears grace-period markers, `autoSuspendEnabled: true` |
| `recordManualPayment` | Owner only | Marks an invoice paid; auto-reactivates **only** if the school was suspended for billing reasons, never overrides a manual pause |

This distinction (billing-suspension vs. manual-pause) matters for a real
SaaS: an Owner might pause a school for a contract dispute unrelated to
payment status — that pause must not evaporate the moment someone pays an
old invoice.

## Security Model additions this module

- `platform_revenue_summary/current`: read-only even for the Owner from
  the client (`allow write: if false`) — only `dailyBillingJob` writes it,
  so the dashboard can't be spoofed by a compromised Owner session either.
- **Suspension gating**: `schoolIsAccessible(schoolId)` does a live `get()`
  on `platform_subscriptions` inside `firestore.rules`, so a suspended
  school loses access to its own tenant data even mid-session (custom
  claims can be stale for up to an hour; this check is not claims-based).
  A user's own profile doc stays readable regardless, so the app can
  render a "school suspended" screen instead of failing silently.
- See `test-rules/suspension.rules.test.ts` for the enforcement tests.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `pause_school_usecase_test.dart` | reason validation, GCash/bank reference requirement |
| Functions | `billingMath.test.ts` | daily/monthly charge math, grace-period deadline math |
| Rules | `suspension.rules.test.ts` | suspended school loses tenant data access, self-profile stays visible |

## Deferred to later modules

- Cross-school invoice list + PDF/Excel export (Reports & Documents modules)
- Owner-side user monitoring / login history table (Security module)
- Full Owner audit trail UI (Audit Trail module — collection already exists)
