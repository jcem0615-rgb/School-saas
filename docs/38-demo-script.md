# Module 38 — The demo script

Everything in the app, in the order to show it, with what to say. Written
for whoever is sitting in front of a principal with a laptop.

**The demo is at https://logicclass.vercel.app.** In-memory data, no
Firebase, nothing to set up. Password for every account below:
see the switcher panel — it prints it.

**How to move between roles:** the round button, bottom-left. It lists
twelve accounts across ten portals and, under each, the one thing worth
opening. Reloading the page puts all the data back.

---

## The 60-second version

If you have one minute, show these three and stop:

1. **Registrar → Admissions.** "Two families enquired three weeks ago and
   nobody has rung them back." That is the number a school loses its year
   to.
2. **Faculty → Grade Submission** (Mathematics, Grade 10 - Rizal). The
   grades are already weighted the DepEd way — written work, performance
   tasks, quarterly assessment — and one student is below 75.
3. **Parent → Payments.** The balance, what it is made of, the
   instalment plan behind it, and Pay Online.

Everything else is depth behind those three.

---

## Owner — the platform above the schools

*Ramon Valdez.* This is you, not the school. One account, bootstrapped
once, and `provisionUser` refuses to create a second owner.

**Do not open this portal in front of a school.** It shows every tenant's
subscription state and revenue, which is every other school's commercial
terms. It is in this document so you know what it does, and it is
deliberately absent from the marketing deck and the feature guide for the
same reason. Show it only to an investor or to yourself.

| Where | What to say |
|---|---|
| Daily / Monthly / Yearly Revenue | Subscription income across every school on the platform |
| Active Students (all schools) | Live head count, all tenants |
| School Management → **Add School** | A school is three documents written in one transaction — half a school is unusable, so it is all or nothing |
| Filters: All / Active / Grace Period / Suspended | Non-payment suspends a tenant; the school sees a message, not a broken app |
| **System Check** | The preflight. Rules deployed, every callable reachable, indexes present, storage writable, owner claim set |

**The line that lands:** "Every other school-management system I have
seen is one school. This one is a platform — you add schools, they never
see each other, and the isolation is in the database rules, not in the
screens."

---

## Director — what the school spends and earns

*Joel Bautista.*

| Button | What it does |
|---|---|
| Attendance Rate Today | Live, from the scans |
| Pending Approvals / **Approvals** | One inbox for every request — material requests, promissory notes |
| Announcements | School-wide, or targeted at sections |
| Meeting Scheduler | With attendees and notices |
| Class Schedule | The timetable, with conflict detection |
| **Reports** | Enrolment by division, collections vs receivables, attendance rates, grade distributions — on screen, as xlsx, as a printable PDF |
| Fee Schedules | What the school charges, per division and year |
| **Payroll** | Next to Expenses on purpose: salaries are the larger |
| Expenses | With spreadsheet import |
| Audit Trail | Every edit and soft delete in the school, written by a trigger nobody can bypass |
| System Check, Data Requests, Emergency Numbers, Leave, Timesheets | |

**Show Payroll.** Pick the month. Every employee, their days worked,
absences, contributions, net pay, and the employer share the school
remits. Then open one and press Print — an A5 payslip, two to a sheet.

**The line:** "Salaries are your biggest cost after nothing, and they
are in a spreadsheet. This reads the same scans your gate already
takes."

---

## Admin — the school's setup

*Grace Mendoza.* Twenty-two tiles; these are the ones to show.

| Button | What it does |
|---|---|
| Employee Management | Staff accounts, HR fields, division scoping |
| Teacher Assignment | Who teaches what, and who advises which section |
| Strands & Programs | SHS strands and college programs |
| **Grading Scheme** | The weights behind every report card — seeded with the DepEd groupings and **confirmed by the school** |
| **Payroll** | SSS, PhilHealth, Pag-IBIG and withholding, typed by the school from its own circulars |
| **Inventory** | Stock room, movement log, reorder list |
| **Admissions** | The enquiry pipeline |
| Fee Schedules, Class Schedule, Reports, Audit Trail, School Branding | |
| System Check | Same preflight the owner has |
| Scan Attendance | The camera, for staff time in and out |

**Open Grading Scheme and stop on the confirmation card.** It says: these
are the DepEd Order 8 s.2015 groupings as a starting point, check them
against the order current for you, and confirm — and no report card
prints until somebody has.

**The line:** "We are not going to tell your school what its grades are.
We seed what the order says and make a person sign off on it. Same for
the SSS table, except there we do not even seed it."

---

## Registrar — the office a family walks up to

*Grace Mendoza.* **The strongest portal to demo.**

| Button | What it does |
|---|---|
| **Admissions** | Enquiry → applied → exam scheduled → exam taken → offered → reserved → enrolled, plus *not accepted* and *withdrew* kept apart |
| Student Records | The roster, with photo, guardians, balance, portal account |
| Year-End Rollover | Promotion and retention for a whole section |
| Grading Scheme | Shared with Admin |
| Online Payments | The review queue for family-submitted payments |
| Payment Setup | The school's e-wallet QR |
| Data Requests | Data Privacy Act: export everything held on a student, or request erasure |

### The admissions walkthrough

Open it. The screen leads with **"N to ring back"** — open enquiries
nobody has moved in a week, longest wait first.

- Tap a family. The stage buttons offered are only the legal ones: one
  step forward, one back, or out. *"You cannot mark somebody as offered
  because that is the outcome you were hoping for."*
- Move one to **Exam scheduled** — it asks for the date. To **Exam
  taken** — it asks for the score and what the paper was out of. To
  **Reserved** — it asks what they paid.
- Then **Enrol**. It creates the student record, once, and carries the
  reservation fee onto their account as a credit.

**The line:** "The reservation is money you have already taken. If it
stays in a notebook, you ask the family for it twice."

### Records & Forms

From a student: **Transcript of Records**, **Form 137**, **Report Card**.
Printing logs the release — who collected it, when, why, how many copies.

### Year-End Rollover

Pick a section. Every student, what the marks recommend, and why:
*"General average 88, every subject passed"*, *"2 subjects below 75:
Mathematics, Science."* Change any row. Then run it.

**The line:** "This is the only thing in the app with no undo, so it is
a plan you read, not a button. And running it twice cannot promote
anybody twice — the record's own id prevents it."

---

## Faculty — the teacher's day

*Maria Santos.*

| Button | What it does |
|---|---|
| My Schedule | Their week |
| Class Attendance | Per subject, with a time in and a time out |
| Coursework | Assignments, quizzes, exams — with answer keys and auto-scoring |
| **Grade Submission** | The class record |
| Material Requests | Into the same approvals inbox |
| Announcements | Targeted at their own sections |
| Messages | Parent–teacher threads |
| Scan Attendance, Emergency Alerts, My Leave, My Timesheet | |

**Grade Submission — the one to demo.** Type *Mathematics* and *Grade 10
- Rizal*, press Load.

- Every student in the section, including the ungraded ones — *"a
  grades-only list can never show you who has not been graded."*
- Each row shows the **computed** grade, the weight group it came from
  ("Science and Mathematics"), and which components are still empty.
- Tap **Submit Grade**: the Component dropdown is Written Work,
  Performance Tasks or Quarterly Assessment.
- **Export / Import** takes a spreadsheet.

**The line:** "In week two there is no quarterly assessment yet. Most
systems count that as a zero and cap every child at 80. This one
rescales it out and tells the teacher what is missing."

---

## Student — what a child sees

*Miguel Torres.*

| Button | What it does |
|---|---|
| Subjects | Tap one: coursework, marks, and the working behind the grade |
| My Timetable | Their week |
| Assignments & Exams | With submissions |
| Subject Attendance, Attendance | |
| Grades | Everything, per term |
| **Payments & Balance** | What is owed and what it is made of |
| **Promissory Note** | Ask to sit the exam and settle later |
| Emergency | An SOS with location, to the whole staff list |
| Announcements, My QR ID | |

**Open a subject.** The grade, its descriptor, and underneath: written
work 142 of 165 at 40%, performance tasks, and *"Still to come:
Quarterly Assessment"*.

**The line:** "The number here and the number on the report card come
from the same function. There is deliberately not a second way to
compute a grade."

---

## Parent — the paying customer

*Rosario Torres.*

| Button | What it does |
|---|---|
| Their children | One card each |
| **Statement of Account** | The full breakdown |
| Grades, Attendance, By Subject, Timetable | |
| **Message a Teacher** | Threads scoped to their own child |
| Pay Online | Upload a screenshot; the registrar reviews it |
| Emergency alerts | For their own children |

**Show the statement.** Tuition, miscellaneous, the sibling discount as
its own line, the ESC grant as another, and the instalment plan with
which lines are paid and which are overdue.

**The line:** "The discount is a record with an approver on it, not a
number somebody typed into the total. Same for the voucher — and the
school can bill DepEd for it because the certificate number is on the
row."

---

## Guidance, Staff, Principal — the rest of the building

**Guidance** *(Cecilia Lim)* — Records, **Student Summons** (which
notifies the student *and* the parent), Emergency Alerts.

**Staff** *(Ricardo Aquino)* — Checklist, Daily Reports, **Inventory**,
Material Requests, My e-ID. Open Inventory: bond paper below its reorder
level, a projector out with a teacher, and a stock count that disagreed
with the books.

**Principal** *(Elena Reyes)* — Student Records, Class Schedule, Teacher
Assignment, Approvals, Announcements. **The head count and no money.**

**The line:** "Roles are not a menu we hide. The principal is refused the
financial figures by the database, not by the screen."

---

## The six documents it prints

Report Card (Form 138) · Transcript of Records · Form 137 · Exam Permit ·
Payslip · Reports pack. All ASCII-safe, because the built-in font drops a
peso sign silently and nobody notices until a parent is holding it.

---

## Questions you will be asked

**"Does it work offline?"** The app needs a connection. Attendance
scanning is the one place that hurts, and it is on the list.

**"Can we import our existing data?"** Students, grades and expenses take
a spreadsheet today, with per-row validation that refuses a bad row
rather than importing it.

**"What about the Data Privacy Act?"** Privacy notice in the app,
recorded consent, per-student export, erasure requests, a stated
retention policy, and a DPA template in the docs.

**"Who can see salaries?"** Director and Admin. Not the principal, not
the registrar. An employee can read their own payslip and nothing else.

**"What if we make a mistake?"** Almost nothing hard-deletes. Payslips,
promotion records, receipt claims and the audit trail cannot be edited at
all — a correction is a new record, which is what makes the old one worth
keeping.

---

## What to be straight about

Say these before you are asked. They are short, and a school that finds
them out later stops trusting the rest.

- **It has not been run against a live Firebase project yet.** The
  preflight exists precisely to prove a deployment before anybody relies
  on it.
- **Contribution tables are not shipped.** The school types SSS,
  PhilHealth, Pag-IBIG and withholding from its own circulars. That is
  deliberate — those rates move, and a wrong bracket is somebody short
  every payday.
- **No overtime, and tardiness is counted but not deducted.** The system
  knows a day was late, not by how much.
- **Attendance needs a connection.**

**The closing line:** "Everything you have just clicked is the real
application. Demo mode swaps the database underneath and nothing else —
same screens, same rules, same arithmetic."
