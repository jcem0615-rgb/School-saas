# Module 35 — Payroll

The school's second-biggest money flow after tuition, and until now the
one the app did not touch. It scanned staff in and out and filed their
leave, and then stopped: `netPay`, `sss`, `philhealth`, `pagibig` and
`withholding` appeared nowhere in the codebase, so the salaries were in
a spreadsheet and everything downstream of them was too.

It builds straight on the timesheet ([Module 29](29-timekeeping.md)),
which already knew the difference between an absence and approved leave,
and already reported the one figure payroll cannot proceed without:
**days somebody scanned in and never out**.

## Nothing is seeded, and that is a decision

The grading scheme ships with the DepEd groupings filled in
([Module 32](32-grading.md)). This one ships **empty**, and the
asymmetry is deliberate.

Those weights are four coarse numbers that have been stable for a decade,
and the risk of shipping them was staleness. SSS, PhilHealth and Pag-IBIG
rates move most years, the withholding table moved with TRAIN and will
move again, and the numbers are fine-grained enough that a wrong one
looks entirely plausible on a payslip. The failure is not an out-of-date
grade: it is an employee under-deducted all year and handed a bill, or
over-deducted and quietly short every payday, and a school remitting the
wrong amount to three agencies.

So this software asserts nothing about what anybody's contribution
should be. The school types the brackets from the circular in front of
them, **records which circular that was**, and confirms. No payslip
issues until they have — and the circular's name is printed beside the
deduction on the payslip, so an employee asking why it is that amount has
somewhere to look.

Saving revokes the confirmation, enforced in the data source rather than
the screen: a table somebody confirmed in January and somebody else
edited in June is not a confirmed table.

### One bracket shape for all four

All four are the same arithmetic underneath — find the bracket, take a
fixed sum, add a percentage of the excess over the bracket's floor:

| | Uses |
| --- | --- |
| SSS | fixed amounts per bracket |
| PhilHealth, Pag-IBIG | percentage, floor at zero |
| BIR withholding | "this much, plus this % of the excess" — the shape in full |

Overlapping brackets are refused. They are the quiet failure: the first
match wins, so the deduction would depend on the order somebody happened
to type the rows in, and two employees on the same salary could come out
different. A *gap* is fine and deliberate — a salary below the lowest
bracket owes nothing.

A salary above every bracket takes the top one rather than nothing.
Deducting zero from the highest earner in the school is a worse way to
find a stale ceiling than deducting the maximum.

## What it computes, and what it refuses to

Basic pay comes from the basis: a monthly salary is the salary whatever
the month held; a daily rate is days actually worked; an hourly rate is
the hours the scans actually show.

**Absences** come off monthly pay at the period's own day rate — the
period's working days as the divisor, not a fixed 22 or 26, because a
fixed divisor pays a short February differently from a long March for no
reason anybody can explain to staff. They never come off hourly pay: the
unworked hours were never in the total, and deducting again would charge
somebody twice for the same absence. And a school can turn deduction off
entirely for staff whose contract simply pays the month.

**Tardiness is reported and not deducted.** The timesheet knows a day was
late; it does not know by how much, because that needs the school's
cutoff and the scan together. Deducting a made-up number of minutes from
somebody's pay is worse than printing "2 days late" and letting the
school decide. The count is on the payslip so the decision has something
to sit on.

**No overtime.** Nothing in this system records authorised overtime, and
inferring it from a late scan-out would pay people for staying behind to
finish their own marking.

**Contributions come off before tax**, which is the whole reason they are
computed in that order — taxing the gross would take more from everybody,
every month.

**Net pay never goes below zero.** A table that would take more than
somebody earned is a misconfiguration, not a negative payslip.

### The semi-monthly switch

Deducting the month's contributions on both cut-offs takes double from
everybody, and it is exactly the kind of mistake nobody notices until one
person checks their own payslip. The run screen has a switch for the
first cut-off, with the reason on it.

### 13th month

PD 851: one twelfth of the **basic** salary earned in the calendar year —
which is why the payslip keeps basic pay apart from gross rather than
only totalling. Computed from what was actually earned, not the monthly
rate times twelve, so somebody who joined in August is owed a twelfth of
what they earned rather than a twelfth of a year they were not here for.

## Where the figures are computed

**On the server, and only on the server.** `runPayroll` reads the pay
rates, the contribution tables, the scans and the approved leave itself.
The client sends a period and which cut-off it is, which is all it is in
a position to know; it cannot send a rate, a day count or a deduction,
and if it does they are ignored.

This was not the original design and the original design was wrong. A
payslip used to be computed on the clerk's device and written straight to
Firestore, with the rules checking only that the clerk held the right
role. Anybody who could reach a console could have issued themselves a
payslip for any figure they liked, and the school's own record would have
agreed with them. Everywhere else money moves in this system the server
recomputes it — `recordPayment` re-reads a balance inside a transaction
rather than trusting the amount the client did the arithmetic on. Payroll
decides what a person is *paid*, and had no equivalent.

It was also wrong for a duller reason. The run screen assembled its
timesheets from two live streams, and a screen that had not finished
loading somebody's scans would have paid them for a month of absences. An
incomplete timesheet looks exactly like a damning one.

### One call, two uses

`runPayroll` takes a `commit` flag. `false` previews and writes nothing;
`true` issues. Deliberately one callable rather than two: the figures the
office approved on screen and the figures that went into the record are
then the same computation, not two that have to be kept in step.

The Dart `computePayslip` survives in `payroll/domain/entities/payslip.dart`
for the demo, which has no server, and is a line-for-line copy of
`functions/src/shared/payroll/payslip.ts`. Both are tested against the
same cases, in both languages, for exactly that reason.

## Issuing

Payslips are keyed `{from}_{to}_{employee}` and written with `create`,
not `set`. Running the same period twice cannot pay somebody twice: the
second run is refused by name — *"already been issued for Maria
Santos"* — and the `create` closes the window the name-checking read
cannot, which is two clerks pressing Issue in the same second. One batch
commits and the other is rejected whole.

Staff with **no pay rate on file are named**, not silently skipped.
Somebody missing from a payroll run is the failure nobody notices until
payday. Somebody with a rate of *zero* is skipped from the run itself —
that is a half-finished compensation record, not somebody who works for
nothing, and issuing them a payslip for nought would say the school had
paid them.

## Printing

The payslip is A5 landscape, so two fit a sheet of A4 — which is how a
school with forty staff actually prints them. Earnings left, deductions
right, net pay boxed, and the basis of every line printed underneath it
("3 days at 1363.64", "SSS Circular 2025-006"). A deduction an employee
cannot trace is one they have to take on trust, and pay is the last place
anybody should be asked to.

The school's logo is printed behind it at 7% opacity, contained and
centred. A payslip leaves the office on its own and comes back months
later attached to a loan application or a barangay clearance, and one
that says only "PAYSLIP" and a name is a page anybody could have typed.
Faint rather than decorative: the figures are what the document is for.
A school with no logo on file, or one that will not load, gets the
payslip without it — a missing letterhead must never be the reason
somebody is not handed their pay.

## Rules

The tightest read list in the tenant. `compensation` is Director and
Admin only — not the principal, not the registrar who handles every
other peso in the building, and not the employee it is about. A salary is
the one number colleagues will read each other's if they can, and a
school where the pay scale leaks has a problem no software fixes
afterwards.

The exception is somebody's **own payslip**, which they can read. They
are handed it on paper anyway, and a system that will not show a person
their own deductions just sends them to ask a person instead.

Payslips are server-written and append-only: `create`, `update` and
`delete` are all denied to every client. The only way one appears is
`runPayroll`. A payslip is a statement of what was paid on a date, and
editing one turns the record of a payday into whatever somebody needs it
to have been. A correction is a fresh payslip.

## Where things are

| Thing | File |
| --- | --- |
| **The run** | `functions/src/callable/payroll/runPayroll.ts` |
| Bracket shape, tables, the lookup | `functions/src/shared/payroll/contributions.ts` |
| Pay bases, the payslip, 13th month | `functions/src/shared/payroll/payslip.ts` |
| The month, from scans and leave | `functions/src/shared/payroll/timesheet.ts` |
| Same three, for the demo | `payroll/domain/entities/contribution_scheme.dart`, `payroll/domain/entities/payslip.dart`, `timekeeping/domain/entities/timesheet.dart` |
| Table validation (overlaps, gaps) | `payroll/domain/usecases/payroll_usecases.dart` |
| Setup screen | `payroll/presentation/screens/payroll_setup_screen.dart` |
| The run screen | `payroll/presentation/screens/payroll_run_screen.dart` |
| The document | `payroll/presentation/documents/payslip_pdf.dart` |
| Firestore | `schools/{id}/compensation/{uid}`, `settings/payroll`, `payslips/{id}` |

Tests: `functions/test/shared/payroll/` (pure, both the arithmetic and
the timesheet), `functions/test/shared/payroll-emulator/` (the callable,
against a real Firestore — who may run it, where the figures come from,
and that a period cannot be issued twice), `test-rules/payroll.rules.test.ts`
(nobody writes a payslip), and the Dart copies under
`app/test/unit/features/payroll/` and `app/test/unit/features/timekeeping/`.
The two implementations are held to the same claims on purpose: a school
seeing one figure on screen and being paid another is the defect this
arrangement exists to make impossible.

The demo seeds tables labelled *"Demo figures, not a real circular"*.
Putting invented numbers there and calling them SSS would be the exact
thing this module refuses to do.
