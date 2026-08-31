const fs = require('fs');
const path = require('path');

// Resolved against this file, not the shell's working directory.
// Run from the repository root, a bare relative path drops the
// document there instead -- which leaves the copy in marketing/
// stale while looking like it was just rebuilt.
const out = (f) => path.join(__dirname, f);
const d = require('docx');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  LevelFormat,
} = d;

const INK = '1E2761', SLATE = '55608A', ACCENT = 'B37418', TINT = 'EEF2FB', RULE = 'D6DEF0';
const CONTENT = 9360;               // 6.5" at 1440 DXA/inch
const COLS = [2340, 2700, 4320];    // sums to CONTENT

// ---------------------------------------------------------------- helpers
const P = (text, o = {}) => new Paragraph({
  spacing: { before: o.before ?? 0, after: o.after ?? 120, line: o.line ?? 264 },
  alignment: o.align,
  indent: o.indent,
  children: [new TextRun({
    text, font: o.font || 'Calibri', size: o.size || 21,
    color: o.color || '2B3350', bold: o.bold, italics: o.italics,
  })],
});

// pageBreakBefore on the heading rather than a standalone break
// paragraph: an explicit break paragraph is itself a line, so a section
// whose content happens to end at the page boundary pushes that empty
// paragraph onto a page of its own and the reader gets a blank sheet.
// Attaching the break to the next heading cannot do that.
const H1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1, pageBreakBefore: true,
  spacing: { before: 0, after: 160 },
  children: [new TextRun({ text, font: 'Cambria', size: 32, bold: true, color: INK })],
});
const H2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2, spacing: { before: 280, after: 120 },
  children: [new TextRun({ text, font: 'Cambria', size: 25, bold: true, color: INK })],
});
const H3 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 90 },
  children: [new TextRun({ text, font: 'Calibri', size: 22, bold: true, color: ACCENT })],
});

const bullets = (items) => items.map((t) => new Paragraph({
  numbering: { reference: 'dots', level: 0 },
  spacing: { after: 70, line: 264 },
  children: [new TextRun({ text: t, font: 'Calibri', size: 21, color: '2B3350' })],
}));

const cell = (text, o = {}) => new TableCell({
  width: { size: o.w, type: WidthType.DXA },
  shading: o.fill ? { type: ShadingType.CLEAR, fill: o.fill, color: 'auto' } : undefined,
  margins: { top: 90, bottom: 90, left: 120, right: 120 },
  children: [new Paragraph({
    spacing: { after: 0, line: 250 },
    children: [new TextRun({
      text, font: 'Calibri', size: o.head ? 19 : 20,
      bold: o.head || o.bold, color: o.head ? INK : '2B3350',
    })],
  })],
});

/** Button | Opens | What you can do there */
const featureTable = (rows, heads = ['Button', 'Opens', 'What you can do there']) => new Table({
  width: { size: CONTENT, type: WidthType.DXA },
  columnWidths: COLS,
  borders: {
    top:    { style: BorderStyle.SINGLE, size: 4, color: RULE },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    left:   { style: BorderStyle.SINGLE, size: 4, color: RULE },
    right:  { style: BorderStyle.SINGLE, size: 4, color: RULE },
    insideHorizontal: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    insideVertical:   { style: BorderStyle.SINGLE, size: 4, color: RULE },
  },
  rows: [
    new TableRow({
      tableHeader: true,
      children: heads.map((h, i) => cell(h, { w: COLS[i], head: true, fill: TINT })),
    }),
    // cantSplit: a row broken across a page boundary leaves its first
    // column's label on one page and the sentence that explains it on the
    // next, which is exactly the thing a reference table must not do.
    ...rows.map((r) => new TableRow({
      cantSplit: true,
      children: r.map((t, i) => cell(t, { w: COLS[i], bold: i === 0 })),
    })),
  ],
});

const note = (text) => new Paragraph({
  spacing: { before: 120, after: 200, line: 264 },
  border: { left: { style: BorderStyle.SINGLE, size: 12, color: ACCENT, space: 10 } },
  indent: { left: 180 },
  children: [new TextRun({ text, font: 'Calibri', size: 20, italics: true, color: SLATE })],
});

const rule = () => new Paragraph({
  spacing: { before: 0, after: 200 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: RULE, space: 6 } },
  children: [],
});

const kids = [];
const add = (...x) => kids.push(...x.flat());

// ---------------------------------------------------------------- cover
add(
  new Paragraph({ spacing: { before: 2600, after: 0 }, children: [
    new TextRun({ text: 'LogicClass', font: 'Cambria', size: 76, bold: true, color: INK }),
  ]}),
  new Paragraph({ spacing: { before: 120, after: 0 }, children: [
    new TextRun({ text: 'One system for the whole school day', font: 'Cambria', size: 32, italics: true, color: ACCENT }),
  ]}),
  new Paragraph({ spacing: { before: 420, after: 0 }, children: [
    new TextRun({ text: 'Feature Guide', font: 'Calibri', size: 30, bold: true, color: '2B3350' }),
  ]}),
  new Paragraph({ spacing: { before: 60, after: 0 }, children: [
    new TextRun({
      text: 'Every screen and every button, portal by portal - for schools evaluating the system.',
      font: 'Calibri', size: 22, color: SLATE }),
  ]}),
);

// ---------------------------------------------------------------- contents
const CONTENTS = [
  '1. What LogicClass is',
  '2. The nine portals at a glance',
  '3. What every portal shares',
  '4. Director Portal',
  '5. Principal Portal',
  '6. Admin Portal',
  '7. Registrar and Cashier Portal',
  '8. Faculty Portal',
  '9. Guidance Portal',
  '10. Staff Portal',
  '11. Student Portal',
  '12. Parent Portal',
  '13. Attendance in detail',
  '14. Fees, assessments and payments',
  '15. Online payments',
  '16. Records and forms',
  '17. The class schedule',
  '18. Reports',
  '19. Emergency',
  '20. Importing and exporting',
  '21. Announcements and notifications',
  '22. Parent and teacher messaging',
  '23. Staff time and leave',
  '24. Signing in when you cannot',
  '25. Security',
  '26. Data Privacy Act',
  '27. Where it runs',
  '28. Going live',
  '29. Admissions',
  '30. Grading and the report card',
  '31. Instalments, discounts and vouchers',
  '32. Official receipts',
  '33. Payroll',
  '34. Inventory',
  '35. Year-end rollover',
  '36. The live demo',
];
// Written out rather than generated as a field: a Word table-of-contents
// field renders blank everywhere until Word itself refreshes it, and this
// document is going to be read as a PDF as often as in Word.
add(H1('Contents'),
  CONTENTS.map((t) => new Paragraph({
    spacing: { after: 60, line: 264 },
    children: [new TextRun({ text: t, font: 'Calibri', size: 21, color: '2B3350' })],
  })));

// ---------------------------------------------------------------- 1
add(
  H1('1. What LogicClass is'),
  P('LogicClass is one application that covers a school day end to end: enrolment and student records, '
    + 'attendance, coursework and grades, fees and payments, printed records and forms, the class timetable, '
    + 'reports, emergencies, and the data-protection paperwork a school is asked for.'),
  P('It is not nine applications with one brand on them. There is one login. Each account carries a role, '
    + 'and the app opens on the portal for that role. Nobody chooses a mode, nobody sees a screen that is '
    + 'not theirs, and nothing has to be copied from one part of the school to another - a mark a teacher '
    + 'submits is the same record a parent reads, and a payment a cashier records is the same figure that '
    + 'moves a balance.'),
  H2('What this guide covers'),
  P('Every portal, every screen, and every button on it. Where a button leads somewhere with its own '
    + 'buttons, that screen has its own table. Cross-cutting features - attendance, fees, records and '
    + 'forms, schedules, reports, emergencies, importing and exporting - are described once in full, in '
    + 'sections 13 to 21, and referred to from each portal that uses them.'),
  H2('The school day it replaces'),
  bullets([
    'A class record, a registrar\'s ledger, a cashier\'s receipt book, a guidance file and an adviser\'s notebook - each holding part of one student.',
    'Attendance called in the morning, written on a slip, and typed into a spreadsheet at the end of the week.',
    'A balance the cashier and the family remember differently, settled only by finding the receipts.',
    'A Form 137 request that takes days, and no record that the document was ever released.',
    'A family that learns about a fever, a suspension or a summons when the child gets home.',
    'A grade that moves, a balance that is edited, a record that disappears - and no way to say who did it.',
  ]),
);

// ---------------------------------------------------------------- 2
add(
  H1('2. The nine portals at a glance'),
  P('One school runs all nine. An account belongs to exactly one of them.'),
  featureTable([
    ['Director', 'School-wide leadership', 'Today\'s figures, announcements, meetings, approvals, fee schedules, expenses, reports, audit trail, system check, data requests.'],
    ['Principal', 'One division', 'Student records, class schedule, teacher assignment, announcements, meetings, approvals, emergency - all limited to their division.'],
    ['Admin', 'School operations', 'Employee accounts, teacher assignment, strands and programs, branding, schedules, fee schedules, reports, audit trail, attendance scanning, leave requests and staff timesheets.'],
    ['Registrar / Cashier', 'The front counter', 'Enrolment, student records, fee assessment, payments and receipts, printed forms, online-payment review and setup, data requests.'],
    ['Faculty', 'Teaching', 'Own timetable, class registers with time in and out, coursework, answer keys, submissions, grade submission, material requests, attendance scanning, messages with parents, own leave and timesheet.'],
    ['Guidance', 'Student welfare', 'Guidance records, student summons, emergency alerts.'],
    ['Staff', 'Non-teaching staff', 'Daily checklist, daily work reports, material requests, own scannable ID, own leave and timesheet.'],
    ['Student', 'The learner', 'Subjects, timetable, coursework, grades, attendance, balance, promissory note, emergency button, announcements, QR ID.'],
    ['Parent', 'The family', 'Each linked child\'s attendance - by day and by subject - timetable, grades and statement of account; messages with their teachers; emergency alerts; announcements; online payment.'],
  ], ['Portal', 'For', 'What it covers']),
  note('Roles that can be scoped to a division - Principal, Registrar, Faculty, Guidance - see only that '
     + 'division\'s records. The limit is enforced by the database, not by hiding buttons.'),
);

// ---------------------------------------------------------------- 3
add(
  H1('3. What every portal shares'),
  H2('3.1 Signing in'),
  featureTable([
    ['Email and password', 'The portal for your role', 'One field each, and a show-password toggle. There is no role picker: the account decides where you land.'],
    ['Remember me', 'Sign in', 'Stores the email so the next sign-in only needs a password. The box comes back ticked with the field filled in; unticking it forgets, which is how a shared front-desk computer is cleared. No password is stored, on any platform, under any setting.'],
    ['Show password', 'Sign in', 'Reveals what has been typed. On every password field in the app, not only this one.'],
    ['Forgot password?', 'Reset password', 'Enter the account email and a reset link is sent.'],
    ['First sign-in', 'Update password', 'An account created with a temporary password must set its own before it can go anywhere.'],
    ['First use', 'Before you start', 'The privacy notice, then the terms of use, in that order - told what is held about you before being asked to agree to anything. Each must be read to the end before its button becomes available, and the version of each is recorded against the account.'],
    ['I do not accept', 'Sign out', 'The terms can be declined, and declining signs you out. The account is untouched and the page comes back next time. The privacy notice has no equivalent: a notice is given, an agreement is entered into.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('3.2 Profile - on every portal\'s top bar'),
  featureTable([
    ['Profile', 'Your own record', 'See your name, role and email; edit your phone number and photo. Role, status and school cannot be changed here by anyone, including you.'],
    ['My QR ID', 'Your school ID', 'The card that identifies you to a scanner. Printable, and usable straight from the screen.'],
    ['Privacy and my information', 'Privacy notice', 'What the school holds, why, and who sees it - plus the button to ask about your own information.'],
    ['My Activity History', 'Your own audit trail', 'Every action you have taken in the system, most recent first.'],
    ['My Attendance', 'Your attendance', 'Every time you were scanned, in and out.'],
    ['Emergency Numbers', 'The school\'s numbers', 'The published list, one tap to dial.'],
    ['Announcements on this device', 'Notification switch', 'Turn push notifications for this phone or computer on or off.'],
  ]),
);

// ---------------------------------------------------------------- 4 Director
add(
  H1('4. Director Portal'),
  P('The Director dashboard opens on four figures for today - the attendance rate, what has been collected, '
    + 'how many approvals are waiting, and the meetings coming up - read at the moment the screen is opened '
    + 'rather than from an overnight job.'),
  H2('4.1 The dashboard buttons'),
  featureTable([
    ['Announcements', 'Announcements', 'Write a title and message, address it to everyone or pick the roles it is for, and pin one to the top. Posting it notifies the phones of the roles addressed.'],
    ['Meeting Scheduler', 'Meeting Scheduler', 'Schedule a meeting with a title, description, location, start and end, and the roles expected. Cancel one that is no longer happening.'],
    ['Approvals', 'Approvals', 'One inbox for every request filed anywhere in the school - material requests from faculty and staff, promissory notes from students. Filter by pending, approved, rejected or all; approve or reject with a reason. Each card carries the request\'s own details, and each decision records who made it. See 4.2.'],
    ['Class Schedule', 'Class Schedule', 'The week for every section. See section 17.'],
    ['System Check', 'System Check', 'Seven readiness checks. See section 25.'],
    ['Data Requests', 'Data Requests', 'What families have asked about their data, and what was answered. See section 23.'],
    ['Reports', 'Reports', 'The four school reports, on screen, to Excel, or printed. See section 18.'],
    ['Fee Schedules', 'Fee Schedules', 'Define the named fee sets the cashier assesses against. See section 14.'],
    ['Expenses', 'Expenses', 'Record school spending with a category, description, amount and date - or import a spreadsheet of it. Financial data: readable by Director, Admin and Registrar only.'],
    ['Emergency Numbers', 'Emergency Numbers', 'Publish the numbers every portal can dial, with who answers, the number, a note and the order they appear in.'],
    ['Audit Trail', 'Audit Trail', 'Every change made in the school, filterable by module and date range, searchable by person or remark.'],
    ['My Activity', 'My Activity History', 'The same trail, narrowed to your own actions.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  note('A Director decides approvals but cannot decide their own request - the rule that files a request '
     + 'and the rule that decides one are deliberately separate.'),
  H2('4.2 What an approval records'),
  P('A request card shows what is being decided, not only its title. The details a request carries - a '
    + 'quantity and an estimated cost for a material request, an amount and a reason for a promissory note '
    + '- are laid out on the card, so nobody approves on a title alone and nobody reading it back months '
    + 'later has to guess what was agreed to.'),
  featureTable([
    ['Filed by', 'Every card', 'The name and role of whoever raised it, and the date and time.'],
    ['The request\'s details', 'Every card', 'Whatever that kind of request carries. The field is free-form - a material request and a promissory note file into the same inbox - so the card lays out the values it finds.'],
    ['Approved / Declined by', 'A decided card', 'The name and role of the account that decided it.'],
    ['Date and time', 'A decided card', 'When the decision was made.'],
    ['Reason', 'A decided card', 'What the decider wrote, on an approval as well as a refusal.'],
    ['Pending / Approved / Rejected / All', 'Filter chips', 'The history, filtered. "All" is the full record of everything ever filed.'],
  ], ['What is shown', 'Where', 'What it tells you']),
  note('The decision is signed by the account that made it: the rules require the deciding account\'s own '
     + 'id and role on the write, so an approval cannot be attributed to somebody else. A history that can '
     + 'be authored is not a history.'),
);

// ---------------------------------------------------------------- 5 Principal
add(
  H1('5. Principal Portal'),
  P('A Principal is a division-level academic leader - Elementary, Junior High, Senior High or College. '
    + 'Their scope is set on their employee record, and every record they can open stops at that line. '
    + 'The role is oversight rather than data entry: grades stay with the teacher who submitted them, and '
    + 'student records stay with the registrar.'),
  featureTable([
    ['Student Records', 'Student Records', 'Search and filter the roster within their division, and open any record in it - read only.'],
    ['Class Schedule', 'Class Schedule', 'The week as it is actually timetabled, section by section.'],
    ['Teacher Assignment', 'Teacher Assignment', 'Who teaches which subject in which section this school year, and who advises the section.'],
    ['Emergency Alerts', 'Emergency Alerts', 'Live alerts raised in the school, with the ability to resolve one.'],
    ['Emergency Numbers', 'Emergency Numbers', 'The published numbers, one tap to dial.'],
    ['Announcements', 'Announcements', 'Post school or division messages under their own name, and pin one.'],
    ['Meeting Scheduler', 'Meeting Scheduler', 'Call a meeting and say who it is for.'],
    ['Approvals', 'Approvals', 'Decide the requests that reach a division head.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  H2('5.1 What a Principal deliberately cannot do'),
  featureTable([
    ['Edit student records', 'Not available', 'Records editing stays the registrar\'s job.'],
    ['Create or edit grades', 'Not available', 'Grading stays faculty-authored.'],
    ['Write guidance records', 'Not available', 'Counselling notes stay a guidance office action; a Principal may read them for their division.'],
    ['Read payments', 'Not available', 'Financial data stays with Director, Admin and Registrar - the same separation drawn for expenses.'],
  ], ['Action', 'Availability', 'Why']),
);

// ---------------------------------------------------------------- 6 Admin
add(
  H1('6. Admin Portal'),
  P('The operator role: the account that keeps the school configured week to week.'),
  H2('6.1 The dashboard buttons'),
  featureTable([
    ['Employee Management', 'Employee Management', 'The staff list, filterable by role and by suspended status. Create an account for any role with first and last name, email, department, position and data-access scope. Export the list or import one from a spreadsheet.'],
    ['Teacher Assignment', 'Teacher Assignment', 'Assign a teacher to a subject, section and school year, and mark one as the class adviser. Import or export the whole set.'],
    ['Strands & Programs', 'Strands & Programs', 'The Senior High strands and college degree programs students enrol into, each with a code. Elementary and Junior High have no catalogue entry - their grade level and section say everything the record needs.'],
    ['Emergency Alerts', 'Emergency Alerts', 'See and resolve alerts raised anywhere in the school.'],
    ['Emergency Numbers', 'Emergency Numbers', 'Publish the numbers every portal can dial.'],
    ['Class Schedule', 'Class Schedule', 'Build the week. See section 17.'],
    ['System Check', 'System Check', 'Seven readiness checks. See section 25.'],
    ['Data Requests', 'Data Requests', 'Answer a family asking about their child\'s data. See section 23.'],
    ['Reports', 'Reports', 'The four school reports. See section 18.'],
    ['Fee Schedules', 'Fee Schedules', 'Define fee sets. See section 14.'],
    ['Announcements', 'Announcements', 'Post and pin school messages.'],
    ['Scan Attendance', 'Scan Attendance QR', 'Open the camera and mark whoever is scanned. See section 13.'],
    ['Audit Trail', 'Audit Trail', 'Every change, filterable by module and date.'],
    ['School Branding', 'School Branding', 'The school\'s printed identity - see 6.3.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  H2('6.2 Inside an employee record'),
  featureTable([
    ['Department, Position', 'Employee detail', 'The HR fields kept against the account.'],
    ['Assigned Division', 'Employee detail', 'Restricts the records this account can read to one division - or leave it unrestricted for a school-wide role.'],
    ['Assigned College Department', 'Employee detail', 'Narrows a college-scoped account further.'],
    ['Save HR Details', 'Employee detail', 'Writes the changes.'],
    ['Reset Password', 'Confirmation', 'Issues a temporary password; the employee is forced to set their own at the next sign-in.'],
    ['Activate / Suspend', 'Confirmation', 'Switches an account off without deleting anything it wrote. An account cannot change its own status, and an Admin cannot suspend a Director.'],
  ], ['Control', 'Where', 'What it does']),
  H2('6.3 School Branding'),
  P('What the school\'s printed output looks like. Everything here appears on ID cards, the Transcript of '
    + 'Records, Form 137 and the printed reports.'),
  featureTable([
    ['Logo', 'Branding', 'Uploaded once; printed on documents and used as the background of the student ID card.'],
    ['School name (as printed)', 'Branding', 'The name as it should appear on paper, which is not always the name in the system.'],
    ['Address line', 'Branding', 'Printed under the name.'],
    ['School year', 'Branding', 'Carried onto documents and used as the default when assessing fees.'],
    ['Principal name and signature', 'Branding', 'An uploaded signature image, printed on IDs and documents.'],
    ['Director name and signature', 'Branding', 'The same, for the school head.'],
    ['Data Protection Officer', 'Branding', 'The name, email and phone a family is told to contact about their data.'],
    ['Save', 'Branding', 'Applies immediately - new ID cards and documents use it from that moment.'],
  ], ['Field', 'Where', 'What it affects']),
);

// ---------------------------------------------------------------- 7 Registrar
add(
  H1('7. Registrar and Cashier Portal'),
  P('The counter a family actually walks up to. Four tiles on the dashboard; everything else opens from a '
    + 'student\'s own record.'),
  H2('7.1 The dashboard buttons'),
  featureTable([
    ['Student Records', 'Student Records', 'The roster, searchable and filterable by division, loading more as you scroll. Register a new student, or import and export the whole list.'],
    ['Data Requests', 'Data Requests', 'The queue of families asking for access, correction, erasure or objection, each with a target answer date and an overdue marker. See section 23.'],
    ['Online Payments', 'Online Payments', 'The review queue of GCash and bank transfers families have sent in. See section 15.'],
    ['Payment Setup', 'Online Payment Setup', 'The school\'s own account name, number, QR image and the instructions families read. See section 15.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  H2('7.2 Registering a student'),
  featureTable([
    ['Register Student', 'Registration form', 'First, last and middle name, division, grade level, section or block, birthday, and guardian name and phone. Senior High and College also pick a strand or program from the catalogue.'],
    ['Register', 'Confirmation', 'Issues a sequential student number - S-2026-000001 - generated on the server so two registrations at once can never collide or reuse one. The record starts enrolled, with a zero balance.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('7.3 Inside a student record'),
  featureTable([
    ['Edit', 'Student detail', 'Name, grade level, section, status and guardian contacts. The student number, the balance and the link to a portal account cannot be edited here by anyone - they are set by the actions that own them.'],
    ['Photo', 'Upload', 'The picture that prints on the school ID.'],
    ['Assess Fees', 'Assess Fees', 'Charge a fee schedule against this student, or type an ad-hoc charge line by line. See section 14.'],
    ['Record Payment', 'Record Payment', 'Take a payment with an amount, purpose, method and reference number, with this student\'s current balance on screen. See section 14.'],
    ['Payment History', 'Payment History', 'Every charge, payment and refund, and a breakdown of how the balance is made up.'],
    ['Records & Forms', 'Records & Forms', 'Print the Transcript of Records or Form 137 and log the release. See section 16.'],
    ['Attendance History', 'Attendance History', 'Every scan for this student, in and out, with the status the server decided.'],
    ['Create Student Portal Account', 'Account creation', 'Issues the student their own login, linked to this record. Shown only while the record has no account - a student record does not need one to exist.'],
    ['Set Balance', 'Balance', 'An opening balance for a student carried over from a previous system.'],
  ]),
);

// ---------------------------------------------------------------- 8 Faculty
add(
  H1('8. Faculty Portal'),
  H2('8.1 The dashboard buttons'),
  featureTable([
    ['My Schedule', 'My Timetable', 'The teacher\'s own week - what they teach, when, where and to whom.'],
    ['Coursework', 'Coursework', 'Every lesson plan, lesson, assignment, project, exam and quiz they have set. See 8.2.'],
    ['Grade Submission', 'Grade Submission', 'Enter marks for a section. See 8.5.'],
    ['Material Requests', 'Material Requests', 'File a request for what the classroom needs; it lands in the same approvals inbox the Director reads.'],
    ['Scan Attendance', 'Scan Attendance QR', 'Mark a class present by scanning their IDs. See section 13.'],
    ['Emergency Alerts', 'Emergency Alerts', 'Raise or read an alert without leaving the room.'],
    ['Announcements', 'Announcements', 'Post to their own sections, under their own name. A teacher can post as themselves and only as themselves.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  H2('8.2 Coursework'),
  P('Six kinds of coursework share one screen, distinguished by a type: Lesson Plan, Lesson, Assignment, '
    + 'Project, Exam and Quiz. The first two are instructional material with no due date and no points; the '
    + 'other four are gradable and must carry a due date.'),
  featureTable([
    ['New', 'Create coursework', 'Type, title, description, subject, section, due date and total points.'],
    ['Publish now', 'Create coursework', 'Left off, the item saves as a draft visible only to staff - a teacher can prepare an exam without it appearing in a student\'s feed.'],
    ['Draft filter', 'Coursework', 'Show only what is not yet published.'],
    ['Answer Key', 'Answer Key', 'See 8.3.'],
    ['Submissions', 'Submissions', 'See 8.4.'],
  ], ['Control', 'Opens', 'What you can do']),
  H2('8.3 Answer key and automatic marking'),
  featureTable([
    ['Correct answers', 'Answer Key', 'One answer per line, in question order.'],
    ['Marks per question', 'Answer Key', 'What each correct answer is worth.'],
    ['Save key and re-mark', 'Answer Key', 'Saves the key and re-marks everything already handed in against it, rather than only future submissions.'],
  ], ['Control', 'Where', 'What it does']),
  H2('8.4 Submissions'),
  featureTable([
    ['The summary line', 'Submissions', 'How many handed in, how many are outstanding, how many were late.'],
    ['Open a submission', 'Mark a student', 'Read the answers and give a score and written feedback.'],
    ['Auto-marked badge', 'Submissions', 'Shown where the answer key scored it, with the question count.'],
    ['Late badge', 'Submissions', 'Marks work handed in after the due date.'],
  ], ['Control', 'Where', 'What it shows']),
  H2('8.5 Grade submission'),
  featureTable([
    ['Subject and Section', 'Grade Submission', 'Pick the class.'],
    ['Load', 'Grade Submission', 'Pulls that section\'s roster.'],
    ['Submit Grade', 'Grade entry', 'Student, term, score and maximum score.'],
    ['Ungraded filter', 'Grade Submission', 'Shows only the students still without a mark for the term.'],
    ['Import / Export', 'Export / Import Grades', 'Bring a term\'s marks in from a spreadsheet, or take the current ones out. See section 20.'],
  ], ['Control', 'Where', 'What it does']),
  note('A grade can be corrected but never reassigned: an update that would move a mark to a different '
     + 'student is refused by the database, not by the screen.'),
);

// ---------------------------------------------------------------- 9 Guidance
add(
  H1('9. Guidance Portal'),
  featureTable([
    ['Guidance Records', 'Guidance Records', 'Enter a student ID, load their records, and add a note with a category and the note itself. Edit an existing note.'],
    ['Student Summons', 'Student Summons', 'Issue a summons with the student, a reason and a scheduled time. Mark one completed, or cancel it.'],
    ['Emergency Alerts', 'Emergency Alerts', 'Every alert raised in the school, with the ability to resolve one.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  H2('9.1 The privacy line between the two records'),
  P('These two features look similar and are deliberately governed differently.'),
  featureTable([
    ['Student Summons', 'Guidance, Director, Admin, the division Principal, the student, and their linked parent', 'Being called to the guidance office is something a family needs to know about, so it follows the same pattern as attendance, grades and payments.'],
    ['Guidance Records', 'Guidance, Director, and the division Principal only', 'Counselling notes are the most closely held record in the system. Not the class adviser, not the student, not the parent.'],
  ], ['Record', 'Who can read it', 'Why']),
);

// ---------------------------------------------------------------- 10 Staff
add(
  H1('10. Staff Portal'),
  featureTable([
    ['Checklist', 'Today\'s checklist', 'A personal task list for the day. Add a task, edit it, tick it off. It is scoped to the person and the date, so it resets rather than piling up.'],
    ['Daily Reports', 'Daily Reports', 'A short end-of-day work log. Submit one; it cannot be edited or deleted afterwards, not even by its author - a correction is a new entry.'],
    ['Material Requests', 'Material Requests', 'The same screen faculty use, filing into the same approvals inbox.'],
    ['My e-ID', 'My School ID', 'The staff member\'s own scannable ID. Staff are scanned rather than scanning, so what they need at hand is the card, not the camera.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  note('The daily report is immutable on purpose: a work log is only worth keeping if it is a trustworthy '
     + 'point-in-time record.'),
);

// ---------------------------------------------------------------- 11 Student
add(
  H1('11. Student Portal'),
  P('A student record exists whether or not the school issues that student a login. Where one is issued, '
    + 'this is what it opens.'),
  featureTable([
    ['Subjects', 'My Subjects', 'Every subject the student is enrolled in and who teaches it. Opening one shows what has been posted in it and the marks recorded for it.'],
    ['My Timetable', 'My Timetable', 'The week, day by day, with room and teacher.'],
    ['Assignments & Exams', 'Assignments & Exams', 'The feed of published coursework, filterable by kind. Drafts never appear here.'],
    ['Open a piece of work', 'Coursework detail', 'Read it, answer question by question, and submit. The answer can be changed while the work is still open, and the mark and the teacher\'s feedback appear here once given.'],
    ['Grades', 'My Grades', 'Marks per subject and term, as the teacher submitted them.'],
    ['Attendance', 'My Attendance', 'Their own record: every scan, in and out.'],
    ['Payments & Balance', 'Payment History', 'What was charged, what was paid, what is left, and the breakdown of how the balance is made up. Read only.'],
    ['Pay online', 'Pay Online', 'Send a fee by GCash or bank transfer and submit the reference for review. See section 15.'],
    ['Promissory Note', 'Promissory Note', 'Ask for an extension with an amount and a reason. It files into the same approvals inbox as every other request.'],
    ['Emergency', 'Emergency', 'One button that alerts the adviser and the linked parents, with a note of what happened. The school\'s published numbers are on the same screen.'],
    ['Announcements', 'Announcements', 'Everything addressed to students.'],
    ['My QR ID', 'My School ID', 'The school ID card, on the phone and printable.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
);

// ---------------------------------------------------------------- 12 Parent
add(
  H1('12. Parent Portal'),
  P('One account can be linked to several children. The dashboard is the list of them; an unresolved '
    + 'emergency alert about any of them is shown as a banner across the top rather than behind an icon, '
    + 'because a push notification can be missed.'),
  featureTable([
    ['A child\'s card', 'Child detail', 'Opens that child, with four tabs.'],
    ['Attendance tab', 'Child detail', 'Every day the child was scanned, and whether it was on time.'],
    ['Timetable tab', 'Child detail', 'Where the child is meant to be, hour by hour.'],
    ['Grades tab', 'Child detail', 'Marks as the teacher submitted them, per subject and term.'],
    ['Statement of Account tab', 'Child detail', 'Charges, payments and the running balance - read only. Refunds are a school action and the button is never rendered here.'],
    ['Pay online', 'Pay Online', 'Send the fee and submit the reference for review. See section 15.'],
    ['Emergency Alerts', 'Emergency Alerts', 'Alerts raised about their own children, with the numbers to call.'],
    ['Announcements', 'Announcements', 'Everything the school addressed to parents.'],
    ['My Activity', 'My Activity History', 'What this account has done in the system.'],
    ['Profile', 'Profile', 'As section 3.2.'],
  ]),
  note('A parent linked to two children sees exactly those two. The query that resolves "my children" is '
     + 'filtered per record by the database, so an unlinked student cannot appear even by accident.'),
);

// ---------------------------------------------------------------- 13 Attendance
add(
  H1('13. Attendance in detail'),
  P('Every person in the school carries a QR ID. Staff-facing roles carry a scanner. The scan decides the rest.'),
  featureTable([
    ['My QR ID / My e-ID', 'My School ID', 'A card layout with the school logo behind it, the holder\'s photo, and the principal and director signatures from Branding. Print it, or present it from the screen.'],
    ['Print ID', 'Print dialog', 'Produces the card as a printable document.'],
    ['Scan Attendance', 'Scan Attendance QR', 'Opens the camera. Point it at a code and the record is written; the screen confirms who was marked and offers Scan Next.'],
    ['Second scan', 'Scan Attendance QR', 'A later scan of the same person on the same day is a time-out, not a duplicate. A third is reported as already completed.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('13.1 Why present or late is decided on the server'),
  P('Whether a scan counts as present or late is compared against the school\'s configured cutoff time in '
    + 'the school\'s own timezone, on the server. It is never computed on the scanning device, so a phone '
    + 'with a wrong - or deliberately changed - clock cannot mark itself on time.'),
  H2('13.2 Who can see attendance'),
  bullets([
    'The person themselves, on My Attendance.',
    'A linked parent, on the child\'s attendance tab.',
    'Staff roles allowed to, within their division scope.',
    'Nobody can write an attendance record from an app at all - only a scan creates one.',
  ]),
  H2('13.3 Attendance per subject'),
  P('The gate scan answers "did they come to school". It cannot answer "were they in Physics", which is '
    + 'the question behind a grade that dropped and the one a parent asks that nobody could previously '
    + 'answer. So each timetabled class has a register of its own.'),
  featureTable([
    ['Class Attendance', 'My classes today', 'The teacher\'s day, in order, with each class either not started, in progress or finished.'],
    ['Time in', 'The register', 'Starts the class. Everybody in the section appears, marked present.'],
    ['P / L / A / E', 'The register', 'Present, late, absent, excused - one tap per exception. Three absences is three taps, not forty.'],
    ['Time out', 'The register', 'Ends the class. The finish time is recorded against everyone who was there.'],
    ['Subject Attendance', 'Student and Parent', 'The same records from the family\'s side, grouped by subject with a rate for each - worst subject first.'],
  ], ['Control', 'Where', 'What it does']),
  bullets([
    'Pressing Time in twice opens the same register, not a second one.',
    'A class not on today\'s timetable cannot be started, so a day\'s marks cannot be filed under the wrong date.',
    'A register can be corrected on the day it was taken, and not afterwards. After that it is the registrar\'s to amend.',
    'An excused lesson still counts as a lesson missed in the rate. A school that dropped them would report a child who missed half a term with a note as having a perfect record.',
  ]),
);

// ---------------------------------------------------------------- 14 Fees
add(
  H1('14. Fees, assessments and payments'),
  H2('14.1 Fee Schedules'),
  featureTable([
    ['New schedule', 'Fee Schedules', 'A schedule name, the division it applies to, an optional grade or year level, and the school year.'],
    ['Add fee', 'Fee Schedules', 'A line with a label and an amount - tuition, miscellaneous, books, whatever the school charges. As many lines as needed; the total is shown as you build it.'],
    ['Offered when assessing', 'Fee Schedules', 'Whether this schedule appears in the cashier\'s list when charging a student.'],
    ['Save schedule', 'Fee Schedules', 'Writes it. Existing assessments are not changed by editing a schedule afterwards.'],
  ], ['Control', 'Where', 'What it does']),
  H2('14.2 Assessing a student'),
  featureTable([
    ['Fee schedule', 'Assess Fees', 'Pick a defined schedule, or choose the ad-hoc option and type the fees line by line.'],
    ['School year', 'Assess Fees', 'Defaults from Branding.'],
    ['Add fee', 'Assess Fees', 'Adds or edits a line before anything is committed.'],
    ['Charge', 'Confirmation', 'Shows the total and asks before writing. The charge is what moves the student\'s balance up.'],
    ['Void', 'Confirmation', 'Reverses an assessment that should not have been made. The voided assessment stays visible - a family\'s account is never quietly rewritten.'],
  ], ['Control', 'Where', 'What it does']),
  H2('14.3 Taking a payment'),
  P('Opened from a student\'s record, the student is already chosen. Opened on its own, the ID is typed - '
    + 'and it has to name somebody before anything is sent.'),
  featureTable([
    ['Student ID', 'Record Payment', 'Either the record\'s ID or the number printed on the ID card, because the number is what a cashier reads off the card in front of them.'],
    ['The student banner', 'Record Payment', 'The name, class and current balance of whoever the ID resolved to - the check that this is the right record, and the figure that proves the deduction afterwards.'],
    ['Record Payment', 'Record Payment', 'Stays disabled until the ID names a student. A payment that cannot name who it is for is not sent.'],
    ['Amount', 'Record Payment', 'What was handed over.'],
    ['Purpose', 'Record Payment', 'What it is for.'],
    ['Payment Method', 'Record Payment', 'Cash, GCash or bank transfer.'],
    ['Reference Number', 'Record Payment', 'The transaction reference, where there is one.'],
    ['Receipt', 'Receipt', 'A sequential receipt number generated on the server, with the date, purpose, reference and who collected it. Two cashiers taking money at the same moment cannot be issued the same number.'],
    ['Refund', 'Confirmation', 'Reverses a payment. Director and Admin only, enforced on the server whatever the screen shows.'],
  ], ['Control', 'Where', 'What it does']),
  H2('14.4 The balance'),
  P('The balance is owned by the server. It moves only inside the same operation that records a payment, a '
    + 'refund or an assessment - there is no path by which an app can simply write a new figure. The '
    + 'breakdown shown to families and to the cashier lists what was charged, what was paid, and what '
    + 'remains, so a balance is never a number nobody can explain.'),
  note('A refund is stored as its own row with a negative amount against the original payment, and the '
     + 'original is marked refunded. Both rows stay in the history.'),
  note('Two cashiers at one counter cannot lose a payment between them. Every balance change is read and '
     + 'written inside one transaction, so two collections at the same moment cannot both start from the '
     + 'same figure - the second is retried against the first rather than landing on top of it. Worth '
     + 'saying because the failure it prevents is invisible: a payment banked, receipted, and simply '
     + 'absent from the balance.'),
);

// ---------------------------------------------------------------- 15 Online payments
add(
  H1('15. Online payments'),
  P('No payment gateway to sign up for and no percentage taken. The school publishes its own account, the '
    + 'family pays through their own app, and a person at the school approves what comes in.'),
  featureTable([
    ['Account name', 'Online Payment Setup', 'The name families will see on their transfer screen.'],
    ['Account / mobile number', 'Online Payment Setup', 'Where to send it.'],
    ['QR image', 'Online Payment Setup', 'The school\'s own payment QR, uploaded so families can scan rather than type.'],
    ['Instructions for families', 'Online Payment Setup', 'The text they read before sending anything.'],
    ['Pay online', 'Pay Online', 'The family\'s side: the account details and QR, then the reference number, the amount sent, the method and the purpose.'],
    ['Awaiting review', 'Online Payments', 'The cashier\'s queue of everything submitted and not yet decided.'],
    ['Approve', 'Online Payments', 'Turns the submission into a real payment with a receipt number, and moves the balance.'],
    ['Reject', 'Online Payments', 'Refuses it, and the family is told.'],
  ], ['Control', 'Where', 'What it does']),
  note('A new submission raises an alert wherever the cashier happens to be in the app, not only on the '
     + 'review screen.'),
  H2('15.1 Paying by bank transfer'),
  P('A school that banks with more than one bank publishes each account - the bank, the account name, the '
    + 'number and the branch. The family chooses which one they sent it to, and that choice is recorded on '
    + 'the submission.'),
  featureTable([
    ['Add bank account', 'Online Payment Setup', 'A bank, an account name, a number, and a branch if the school banks at more than one.'],
    ['Stop offering this', 'Online Payment Setup', 'Closes an account. It stays on file, because older submissions point at it; it is simply no longer offered.'],
    ['Bank Transfer', 'Pay Online', 'Offered only when the school has published at least one open account. The family picks which one and the details are on screen to copy.'],
    ['Sent to', 'Online Payments', 'Which account the family says they used, beside the reference number - so the cashier knows which statement to check.'],
  ], ['Control', 'Where', 'What it does']),
  note('A cashier holding a reference number and three bank statements has to know where to look. That is '
     + 'the whole reason the destination is recorded.'),
);

// ---------------------------------------------------------------- 16 Records
add(
  H1('16. Records and forms'),
  P('The two documents a school is asked for most, generated from the records already held rather than '
    + 'copied out by hand.'),
  featureTable([
    ['Transcript of Records', 'Records & Forms', 'The student\'s academic record, laid out on the school\'s own letterhead - logo, printed name, address, school year, and the principal and director signatures from Branding.'],
    ['Form 137', 'Records & Forms', 'The DepEd permanent record form, with the fields that form carries.'],
    ['Purpose', 'Records & Forms', 'Why the document is being released.'],
    ['Released to', 'Records & Forms', 'The person receiving it, and their relationship to the student.'],
    ['Remarks', 'Records & Forms', 'Anything else worth recording at the moment of release.'],
    ['Release & print', 'Print dialog', 'Produces the document and writes the release to the history in the same action.'],
    ['Print again', 'Print dialog', 'A reprint, recorded as a reprint, so the count of copies in circulation stays honest.'],
    ['Copies / history', 'Records & Forms', 'Every release of this document for this student, with its date, purpose, recipient and who released it.'],
  ], ['Control', 'Where', 'What it does']),
  note('When the receiving school writes back years later asking when Form 137 was sent and to whom, the '
     + 'answer is on the screen.'),
);

// ---------------------------------------------------------------- 17 Schedule
add(
  H1('17. The class schedule'),
  featureTable([
    ['Add class', 'Schedule editor', 'Subject, section, teacher, room, day, start time and end time.'],
    ['Starts / Ends', 'Schedule editor', 'Times are read the way people type them - 7:30 AM, 7:30am, 07:30, 0730 are all understood.'],
    ['Save', 'Schedule editor', 'Refused if it clashes: two classes in the same room, the same teacher in two places, or one section double-booked. The conflict is named. The same check runs again on the server before anything is written.'],
    ['Remove', 'Confirmation', 'Deletes a block from the week.'],
    ['Section filter', 'Class Schedule', 'The week for one section.'],
    ['Print', 'Print dialog', 'The week as a wall-chart grid. Where the section or the teacher is the same all the way down a column, it is printed once rather than in every cell.'],
  ], ['Control', 'Where', 'What it does']),
  H2('17.1 The same blocks, four ways'),
  bullets([
    'Admin and Director see the whole school\'s week, section by section.',
    'A Principal sees their division.',
    'A teacher sees their own week, on My Schedule.',
    'A student sees theirs, and a parent sees their child\'s.',
  ]),
);

// ---------------------------------------------------------------- 18 Reports
add(
  H1('18. Reports'),
  featureTable([
    ['Enrollment by Division', 'Reports', 'Head count by division and grade level, every status shown - not only the enrolled ones. The date range does not apply: this is a head count, not a period figure.'],
    ['Collections and Receivables', 'Reports', 'What was charged, what came in, and what is still owed over the chosen period.'],
    ['Attendance Rate by Section', 'Reports', 'Present, late and absent by section, with the rate. Excused days sit outside the rate rather than counting against it.'],
    ['Grade Distribution by Subject', 'Reports', 'Marks banded against the DepEd descriptors, per subject.'],
    ['This school year / This month / Last 30 days', 'Reports', 'The period the report covers. The school year runs June to March.'],
    ['Export to Excel', 'File save', 'The same table as a spreadsheet.'],
    ['Print', 'Print dialog', 'A PDF with the school\'s heading and the totals row shaded.'],
  ], ['Report or control', 'Where', 'What it gives you']),
);

// ---------------------------------------------------------------- 19 Emergency
add(
  H1('19. Emergency'),
  featureTable([
    ['Emergency (student)', 'Emergency', 'One button, with a note of what happened. Sending it notifies the student\'s adviser and their linked parents.'],
    ['Emergency Alerts (staff)', 'Emergency Alerts', 'Live alerts raised in the school. Faculty, Guidance, Principal, Admin and the Director can see them, and any of them can resolve one.'],
    ['Resolve', 'Emergency Alerts', 'Closes an alert, recorded with who resolved it and when.'],
    ['Emergency Alerts (parent)', 'Emergency Alerts', 'Alerts about their own children, with the numbers to call. An unresolved one also appears as a banner on the parent dashboard.'],
    ['Emergency Numbers', 'Emergency Numbers', 'The school\'s published list - clinic, guard, barangay, hospital - each with who answers, the number, a note and its position in the list. One tap dials.'],
    ['Add number', 'Emergency Numbers', 'Director and Admin publish and reorder the list.'],
  ], ['Control', 'Where', 'What it does']),
);

// ---------------------------------------------------------------- 20 Import/export
add(
  H1('20. Importing and exporting'),
  P('A school changing systems has years of data in spreadsheets. Five lists can be moved in and out '
    + 'without retyping.'),
  featureTable([
    ['Students', 'Student Records', 'The roster, with divisions, sections and guardian details.'],
    ['Employees', 'Employee Management', 'Staff with department, position and division scope.'],
    ['Grades', 'Grade Submission', 'A term\'s marks, per subject and section.'],
    ['Expenses', 'Expenses', 'School spending, by category and date.'],
    ['Teacher assignments', 'Teacher Assignment', 'Who teaches what, to whom, this school year.'],
  ], ['List', 'Where', 'What moves']),
  H2('20.1 The controls, on every one of them'),
  featureTable([
    ['Export', 'Export / Import sheet', 'Downloads the current list as .xlsx.'],
    ['Export as CSV instead', 'Export / Import sheet', 'The same data in plain CSV.'],
    ['Download blank template (.xlsx)', 'Export / Import sheet', 'The exact column shape the import expects - so there is no guessing, and no phone call about which columns are needed.'],
    ['Choose an Excel or CSV file', 'Preview', 'Reads the file and shows what it found before writing anything. Rows it cannot read are reported rather than silently skipped.'],
  ], ['Control', 'Where', 'What it does']),
);

// ---------------------------------------------------------------- 21 Announcements
add(
  H1('21. Announcements and notifications'),
  featureTable([
    ['Title and Message', 'Announcements', 'What is being said.'],
    ['Everyone / Choose roles', 'Announcements', 'Who it is addressed to. Choosing roles means only those roles see it - and only their phones ring.'],
    ['Pin to top', 'Announcements', 'Keeps one announcement at the top of the list for everyone who can see it.'],
    ['Announcements on this device', 'Profile', 'The reader\'s own switch for push notifications on that phone or computer.'],
  ], ['Control', 'Where', 'What it does']),
  H2('21.1 How a notification reaches a phone'),
  P('Posting an announcement resolves its audience on the server, finds the active accounts in the school '
    + 'whose role is addressed, and sends to the devices those accounts have registered. It arrives with '
    + 'the app closed. The app is installable to a home screen as a progressive web app, which is what '
    + 'makes this work on a phone without an app store install.'),
  P('Who a list shows and whose phone rings are decided by two separate pieces of code, kept deliberately '
    + 'apart and covered by the same table of test cases - so a change to one cannot quietly disagree with '
    + 'the other.'),
  H2('21.2 The notification inbox'),
  P('A push notification is gone the moment it is swiped away, and never arrives at all for a phone that '
    + 'was off or a browser that never granted permission. So everything the school sends is also written '
    + 'to the person\'s own inbox, reached from the bell in every portal\'s top bar and still there '
    + 'tomorrow.'),
  featureTable([
    ['Bell', 'Every portal', 'Carries the count of what has not been read.'],
    ['Notifications', 'The inbox', 'Everything sent to this person, newest first, with what it was about.'],
    ['Turn on notifications', 'The inbox', 'Where permission is asked - on the screen somebody opened to look at notifications, not as a prompt in front of somebody checking a grade.'],
    ['Mark all read', 'The inbox', 'Clears the count.'],
  ], ['Control', 'Where', 'What it does']),
  H2('21.3 What raises one'),
  featureTable([
    ['An announcement', 'Everyone it is addressed to'],
    ['A guidance summons', 'The student and every linked parent - and again if it is cancelled'],
    ['An emergency alert', 'The class adviser and the student\'s parents'],
    ['A leave decision', 'The employee who filed it'],
    ['A message', 'The other person in the conversation'],
  ], ['What happened', 'Who is told']),
  note('A summons has always been visible to the family. Visible is not told, and a summons is the one '
     + 'record with a date it is no use learning about afterwards - so it is now sent, and sent again if '
     + 'the office calls it off. A family that rearranged a working day around an appointment should not '
     + 'turn up to one that is off.'),
);

// ---------------------------------------------------------------- 22
add(
  H1('22. Parent and teacher messaging'),
  P('A parent and one of their child\'s teachers can message each other in the app. One thread per '
    + 'teacher, per parent, per child - so a parent with two children taught by the same teacher has two '
    + 'threads, and neither side has to say which child they mean.'),
  H2('22.1 Who can message whom'),
  P('A parent may write to a teacher when that teacher teaches their child. The school does not configure '
    + 'this and nobody maintains a list: it is worked out from the timetable assignments, the student\'s '
    + 'section and the parent\'s linked children, every time a thread is opened.'),
  featureTable([
    ['Parent', 'Any teacher assigned to their child\'s class. The class adviser is offered first.'],
    ['Teacher', 'The linked guardians of any student in a class they teach.'],
    ['Everybody else', 'Nobody. Messaging is between a family and the teacher who teaches their child.'],
  ], ['Who', 'May write to']),
  H2('22.2 Who can read it'),
  P('Only the two people in it. Not the Principal, not the Director, not an administrator. This is '
    + 'deliberate: a parent who believes the office is reading tells the teacher nothing worth reading, and '
    + 'a channel nobody trusts is a channel nobody uses. A school that needs to see a conversation has a '
    + 'lawful-request route and an audit trail; what it does not have is a login that quietly opens every '
    + 'private message in the school.'),
  H2('22.3 What is fixed and what is not'),
  bullets([
    'A message cannot be edited, and cannot be unsent. It is the record of what was said.',
    'The sender is stamped by the server, so nobody can post in the other person\'s name.',
    'Each side clears only its own unread count - marking your own as read does not clear theirs.',
    'Every message raises a notification for the other person, naming the child it is about.',
  ]),
  note('Announcements remain the way to tell a whole class or a whole school something. Messaging is for '
     + 'one family and one teacher.'),
);

// ---------------------------------------------------------------- 23
add(
  H1('23. Staff time and leave'),
  P('The QR scanner has always been able to scan an employee in and out. This is where those scans are '
    + 'read back as a month, together with the leave the office approved - which is the piece that turns a '
    + 'blank day from an unexplained absence into an authorised one.'),
  H2('23.1 Filing leave'),
  P('Any employee files from My Leave: the kind of leave, the dates, and why. The system counts the '
    + 'working days for them, weekends excluded, and stores that count so a request keeps the number it '
    + 'was approved on. A request can be withdrawn while it is still undecided, and not after.'),
  H2('23.2 Deciding it'),
  P('Director, Principal and Admin see every request in one queue, with the decided ones beneath it. A '
    + 'decision records who made it, in what role, when, and any remarks - and the employee is notified. '
    + 'A request that has already been decided cannot be decided again.'),
  H2('23.3 The timesheet'),
  P('A month, per employee, for the office - and their own for every employee. Each day is named as '
    + 'exactly one thing:'),
  featureTable([
    ['Worked / Late', 'There is a scan. Late still counts as present.'],
    ['On leave', 'An approved request covers the day. A pending one does not.'],
    ['Rest day', 'Saturday or Sunday by default, configurable for schools that teach on Saturdays.'],
    ['Absent', 'A working day with no scan and no approved leave.'],
  ], ['Reads as', 'When']),
  bullets([
    'A scan beats leave: somebody who came in on their approved leave day was at work.',
    'A day with a time in and no time out contributes no hours at all, and the sheet says how many such days there are. Nothing is guessed onto a payslip.',
    'Totals: days worked, hours, lates, days on leave, days absent.',
  ]),
  note('This is the sheet payroll is run from. The run itself is section 33.'),
);

// ---------------------------------------------------------------- 24
add(
  H1('24. Signing in when you cannot'),
  P('Two routes back into an account, because the people who need one do not all have the same things.'),
  featureTable([
    ['Reset by email', 'A link is emailed to the address on the account.'],
    ['Reset by phone', 'A code is texted to the mobile number on the account. The person then chooses a new password.'],
  ], ['Route', 'What happens']),
  P('The phone route exists because a family whose only device is the handset in their pocket often has no '
    + 'email they can reach - and the account they cannot get into is frequently the one the school emailed '
    + 'the invitation to.'),
  H2('24.1 What it will not do'),
  bullets([
    'It will not recover an account when the number is registered to more than one - a parent who also works at the school, or a household sharing a handset. It says so and asks them to contact the office.',
    'It will not recover a suspended or closed account.',
    'It signs out every other session on the account, because somebody recovering an account is often doing it because somebody else has it.',
  ]),
  note('This is only as good as the mobile numbers on your records. A school that never filled the field in '
     + 'has given its families a route that finds nothing.'),
);

// ---------------------------------------------------------------- 25 Security
add(
  H1('25. Security'),
  P('Every rule below is enforced where the data lives rather than in the app, so it holds even for a '
    + 'request that never went through the app at all.'),
  H2('25.1 One school cannot see another'),
  P('Every record lives under its own school, and every account carries the school it belongs to. There is '
    + 'no query that crosses that line, for any role.'),
  H2('25.2 Divisions hold too'),
  P('A Principal, Registrar, Faculty member or Guidance counsellor can be scoped to Elementary, Junior '
    + 'High, Senior High or College - and, for College, to a department. A Junior High teacher scoped to '
    + 'their division cannot open a Senior High record: the read is denied, not filtered out of a list.'),
  H2('25.3 Fields the app can never write'),
  featureTable([
    ['balance', 'Only a recorded payment, refund or assessment', 'A balance that could be typed is a balance nobody can trust.'],
    ['studentNumber', 'Only registration', 'A permanent identifier, issued once.'],
    ['role, status, schoolId', 'Only the dedicated actions that audit them', 'A role change is a security event and is recorded as one.'],
    ['attendance', 'Only a scan', 'Cross-user writes are not something a client should be trusted with.'],
    ['receipt numbers', 'Only the server', 'Two cashiers at once must not be able to issue the same number.'],
  ], ['Field or record', 'Written by', 'Why']),
  H2('25.4 Everything is written down'),
  P('Every create, edit and delete in the school lands in the audit trail with who did it and when, and it '
    + 'is recorded automatically rather than because a screen remembered to log it. The Director and Admin '
    + 'read the whole trail, filtered by module and date range; every account can read its own.'),
);

// ---------------------------------------------------------------- 26 Privacy
add(
  H1('26. Data Privacy Act'),
  P('Schools hold minors\' records. These are the questions a Data Protection Officer asks, and where the '
    + 'answer lives in the system.'),
  featureTable([
    ['A privacy notice', 'In the app', 'Eight categories of data: what is held, why it is held, and who sees it. Plus the rights the Act names, the retention position, and how the school secures and shares data.'],
    ['A recorded acknowledgement', 'First sign-in', 'Every account reads the notice before their first use, and the version they read is stored against the account.'],
    ['Access requests', 'Profile > Privacy and my information', 'A family can ask what is held about their child, from their own account.'],
    ['Correction, erasure, objection', 'Same screen', 'The other rights the Act names, filed the same way.'],
    ['The queue', 'Data Requests', 'Director, Admin and Registrar see every request with its kind, its target answer date and whether it is overdue. Each is answered as done or refused, with the reason recorded.'],
    ['A retention schedule', 'Shipped with the system', 'How long each kind of record is kept, written down.'],
    ['A Data Processing Agreement', 'Shipped with the system', 'A template ready for the school\'s DPO to review.'],
    ['The DPO\'s contact details', 'Branding', 'The name, email and phone a family is told to contact.'],
  ], ['What a DPO asks for', 'Where it is', 'What it contains']),
);

// ---------------------------------------------------------------- 27 Platforms
add(
  H1('27. Where it runs'),
  featureTable([
    ['Android', 'An APK the school distributes', 'Camera scanning and push notifications, on the phones staff already carry. No app store account is needed on the school side.'],
    ['Windows', 'A desktop build', 'For the registrar\'s and cashier\'s counter, where the printing and the typing happen.'],
    ['Web', 'Any browser', 'Installable to the home screen as a progressive web app, including on iPhone once added to the Home Screen.'],
  ], ['Platform', 'How it is delivered', 'Notes']),
  P('It is one codebase and three builds, not three products - so a fix reaches the registrar\'s desktop '
    + 'and the parent\'s phone together, and there is no separate teacher app or parent app to keep in step.'),
);

// ---------------------------------------------------------------- 28 Going live
add(
  H1('28. Going live'),
  P('A readiness check the school can run itself, from the Director or Admin portal, before the first '
    + 'school day. Nothing runs until it is asked to, and nothing it does changes the school\'s data.'),
  featureTable([
    ['Database reachable', 'Pass', 'A real read from the school\'s own records returns.'],
    ['Security rules deployed', 'Pass', 'A write the rules must refuse is refused. This is the check that matters most: a database left in test mode behaves perfectly right up to the day one school reads another\'s records.'],
    ['Cloud Functions deployed', 'Pass', 'Every server action answers, in the right region.'],
    ['Database indexes created', 'Pass', 'The queries the app depends on actually run.'],
    ['File storage writable', 'Pass', 'A probe file is written and removed again.'],
    ['Account claims set', 'Pass', 'The signed-in account carries its role and its school.'],
    ['School details filled in', 'Warning', 'Name, logo, school year, principal and DPO. A warning rather than a failure - the system works without them, the printed documents just look unfinished.'],
  ], ['Check', 'Result type', 'What it proves']),
  note('Every failure names its remedy. A check that cannot say what to do about it is not a check, it is '
     + 'an alarm.'),
);


// ---------------------------------------------------------------- 29 Admissions
add(
  H1('29. Admissions'),
  P('The pipeline in front of enrolment: an enquiry becomes an applicant, an applicant becomes a student. '
    + 'Opened from the Registrar portal, and the screen opens on the enquiries nobody has moved in a week, '
    + 'longest wait first - because that list is the one a school loses a year to.'),
  H2('29.1 The seven stages'),
  featureTable([
    ['Enquiry', 'Somebody asked', 'Name, contact number, the grade level applied for, and where the family heard about the school.'],
    ['Applied', 'The form is in', 'With the documents the school asked for listed against the record.'],
    ['Exam scheduled', 'A date is set', 'And the family is told it.'],
    ['Exam taken', 'A score exists', 'Without a score the stage will not move. The app will not record an exam as taken because somebody expects it to have been.'],
    ['Offered', 'A place is offered', 'With the date the offer lapses.'],
    ['Reserved', 'A fee is paid', 'The reservation fee follows the child and lands as a credit on their ledger once they enrol.'],
    ['Enrolled', 'A student exists', 'One server transaction creates the student record and issues the student number.'],
  ], ['Stage', 'Means', 'What it needs']),
  H2('29.2 The buttons'),
  featureTable([
    ['New Enquiry', 'Applicant form', 'Name, contact, grade level applied for, source, and any remarks.'],
    ['Advance', 'Stage picker', 'Offers only the stages that legally follow this one: one step on, one step back, or out. There is no free choice of stage.'],
    ['Decline / Withdraw', 'Applicant', 'Ends the pipeline for this family, with a reason. Neither counts as a stage reached.'],
    ['Enrol', 'Confirmation', 'Available only from Reserved. Creates the student, issues the number, and posts the reservation fee as a credit.'],
    ['Follow-up list', 'Applicants', 'Every open applicant nobody has touched in a week, oldest wait first.'],
    ['Funnel', 'Admission funnel', 'How many reached each stage this year, and where the drop-off is.'],
  ], ['Control', 'Opens', 'What happens']),
  note('A stage cannot be wished forward. No score, no "exam taken"; no payment, no "reserved". The '
     + 'evidence is what moves the record, which is the only reason the funnel means anything.'),
);

// ---------------------------------------------------------------- 30 Grading
add(
  H1('30. Grading and the report card'),
  P('Grades are weighted the way DepEd Order 8 s.2015 describes: written work, performance tasks and '
    + 'quarterly assessment, weighted differently per subject group, then transmuted for the report card.'),
  H2('30.1 The grading scheme'),
  featureTable([
    ['Grading Scheme', 'Admin portal', 'The weights per subject group, and the transmutation table. Shipped seeded with the Order 8 groupings as a starting point - not as an answer.'],
    ['Edit weights', 'Grading Scheme', 'Change any weight. The three components of a group must total 100.'],
    ['Confirm', 'Grading Scheme', 'A named person at the school states that these weights match the order current for them, and that name is stored.'],
    ['Any edit', 'Grading Scheme', 'Revokes the confirmation. A changed scheme has to be confirmed again before anything prints.'],
  ], ['Control', 'Where', 'What happens']),
  H2('30.2 How a quarterly grade is computed'),
  bullets([
    'Each score is a raw mark out of a maximum, filed under one of the three components.',
    'A component with no work in it yet is left out of the arithmetic entirely - it is not a zero.',
    'The grade is the earned total rescaled over the weight that actually exists, and the screen names which component is still missing.',
    'That is the difference between "no exam has been given yet" and "every child in the school is capped at 80 until it has".',
  ]),
  H2('30.3 The report card'),
  featureTable([
    ['Submit Grades', 'Faculty portal', 'Enter marks by hand, or import a spreadsheet. The class record shows the arithmetic behind every grade.'],
    ['Print Form 138', 'Report card', 'Every subject, every quarter, the final grade, the DepEd descriptor and the remarks - on the school\'s own letterhead.'],
    ['Unconfirmed scheme', 'Refusal', 'The report card will not print at all until somebody at the school has confirmed the weights. This is deliberate.'],
  ], ['Control', 'Opens', 'What happens']),
  note('The weights are the school\'s, not ours. We seed them so nobody starts from a blank table, and then '
     + 'we refuse to print anything until a named person has checked them.'),
);

// ---------------------------------------------------------------- 31 Billing
add(
  H1('31. Instalments, discounts and vouchers'),
  P('Section 14 covers charging a fee and taking a payment. This section covers the four things a '
    + 'Philippine private school then does to that bill - and none of them is a remark typed into a notes '
    + 'field.'),
  H2('31.1 Instalments'),
  featureTable([
    ['Billing Schedule', 'Fee schedule', 'Split a schedule into parts - upon enrolment, then monthly - each with its own amount and due date.'],
    ['Due dates', 'Statement', 'What is overdue becomes a date the family and the cashier can both read, rather than an opinion at a counter.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('31.2 Discounts'),
  featureTable([
    ['Grant Discount', 'Discount', 'Kind - sibling, early bird, staff child, scholarship - amount or percentage, the charge it applies to, and the authority it was granted on.'],
    ['Revoke', 'Discount', 'Ends it. The original grant and the revocation both stay on the record.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('31.3 ESC and SHS vouchers'),
  P('A voucher is a subsidy owed to the school by PEAC, not a discount the school gave away. It is carried '
    + 'as a receivable: the family sees the net they owe, and the school still sees what is outstanding '
    + 'from the programme. A school that books a voucher as a discount cannot say what PEAC still owes it.'),
  H2('31.4 The exam permit'),
  P('Cleared or not cleared, read from the ledger, so nobody is deciding at a desk on exam morning whether '
    + 'this family is up to date. A promissory note recorded against the account is what clears a student '
    + 'the school has decided to let sit.'),
);

// ---------------------------------------------------------------- 32 Receipts
add(
  H1('32. Official receipts'),
  P('The BIR register a school keeps by hand in a booklet, kept in the app instead - with the one property '
    + 'a paper booklet has for free and software usually loses: a serial is issued exactly once.'),
  featureTable([
    ['Register Booklet', 'OR booklet', 'The Authority to Print number, the serial range it covers, and the date it was received.'],
    ['Issue OR', 'Official receipt', 'Claims the next serial from the open booklet, on the server, inside a transaction. Two cashiers pressing at the same moment are handed different numbers - never the same one.'],
    ['Print', 'Official receipt', 'Payer, amount, what it was for, and the serial, on the school\'s own letterhead.'],
    ['Cancel', 'Official receipt', 'Marks a serial cancelled. It is never re-issued to somebody else.'],
    ['Reconcile', 'OR register', 'Which serials were issued, which were cancelled, and which are simply missing - the question an audit opens with.'],
  ], ['Control', 'Opens', 'What happens']),
  note('The serial is not a number the app displays. It is a number the server gives out once and can '
     + 'never give out again.'),
);

// ---------------------------------------------------------------- 33 Payroll
add(
  H1('33. Payroll'),
  P('The timesheet in section 23 is the input. This is the run: a period, a set of employees, and a '
    + 'payslip each.'),
  H2('33.1 Setting it up'),
  featureTable([
    ['Compensation', 'Employee', 'Basis - monthly, daily or hourly - the rate, and any allowances. Director and Admin only, enforced by the database.'],
    ['Contribution Scheme', 'Payroll Setup', 'The SSS, PhilHealth, Pag-IBIG and withholding brackets. It ships EMPTY.'],
    ['Confirm', 'Payroll Setup', 'A named person states that these brackets came from the circular in front of them, names that circular, and confirms. No payslip prints until they have.'],
  ], ['Control', 'Opens', 'What happens']),
  H2('33.2 The run'),
  bullets([
    'Days worked, late and absent come from the month already on the timesheet - nothing is retyped.',
    'An absence is costed at the period\'s own day rate, not a fixed twenty-two, so February does not pay differently from March.',
    'Contributions are deducted first, and tax is computed on what is left.',
    'Net pay never falls below zero.',
    '13th month is a twelfth of what was actually earned across the year, taken from the runs rather than from a headline salary.',
  ]),
  H2('33.3 The payslip'),
  featureTable([
    ['Print Payslips', 'Payslip', 'A5, two to a sheet, with the basis of every line on it - so an employee can check their own pay without asking anybody.'],
    ['My Payslips', 'Own payslips', 'An employee can read their own, and nobody else\'s. Payslips are create-only: a correction is a new payslip.'],
  ], ['Control', 'Opens', 'What happens']),
  note('We ship no contribution tables. Rates move most years, a wrong bracket looks entirely plausible on '
     + 'a payslip, and the result is somebody short every payday or handed a bill in December. Your school '
     + 'types them from the circular, records which circular that was, and confirms - and that name prints '
     + 'beside the deduction.'),
);

// ---------------------------------------------------------------- 34 Inventory
add(
  H1('34. Inventory'),
  P('The stock room, as a ledger. Every movement is a row, and the quantity on hand is what those rows add '
    + 'up to - it is never a number somebody typed.'),
  featureTable([
    ['Add Item', 'Item', 'Name, category, unit, reorder level, and where in the school it is kept.'],
    ['Receive', 'Movement', 'A delivery, with the supplier and the document number against it.'],
    ['Issue', 'Movement', 'To a named person, for a reason. The projector has a name against it from the moment it leaves the room.'],
    ['Return', 'Movement', 'Back on the shelf, and the person who had it is clear.'],
    ['Consume / Write off', 'Movement', 'Used up, or damaged and gone. Both are movements, so both are explained.'],
    ['Low Stock', 'Report', 'What has fallen to its reorder level, before somebody needs it.'],
    ['Outstanding', 'Report', 'What is out of the room right now, and who is holding each of it.'],
  ], ['Control', 'Opens', 'What happens']),
  note('The movement and the new quantity are written in one transaction, and each movement stores the '
     + 'quantity before and after it. A count that looks wrong has a history that explains it.'),
);

// ---------------------------------------------------------------- 35 Year-end
add(
  H1('35. Year-end rollover'),
  P('The week every April that a school currently does by hand, on a printed list, in a room. Run from the '
    + 'Registrar portal, one decision per student, against the final grades already held.'),
  featureTable([
    ['Promoted', 'Next grade level', 'Taken from the school\'s own roster of levels. Where there is no next level, the app says so rather than inventing one.'],
    ['Retained', 'Same grade level', 'With a reason recorded where the school needs one.'],
    ['Graduated', 'Exit', 'For students in the last level of a division, read off the roster rather than hard-coded.'],
    ['Transferred out', 'Exit', 'The record stays; the student does not roll forward.'],
    ['Held', 'Nothing', 'The default. A student the school has not decided on is left out of the run entirely.'],
  ], ['Decision', 'Effect', 'What it means']),
  bullets([
    'Silence never becomes a promotion: held students are excluded from the run, not defaulted through it.',
    'A student already rolled over is skipped rather than moved twice, so the run is safe to repeat.',
    'The run reports how many were applied and how many were already done.',
    'A promotion record is written once and never edited. A correction is a new record.',
  ]),
);

// ---------------------------------------------------------------- 36 Demo
add(
  H1('36. The live demo'),
  P('Everything in this guide can be clicked through at logicclass.vercel.app, with no sign-up, no '
    + 'install, and no Firebase project behind it.'),
  bullets([
    'An account for every portal. The round button at the bottom left switches between them and names, under each, the one screen worth opening.',
    'The data is in memory. Nothing typed into it is kept, and reloading the page puts it all back.',
    'Every screen there is the real application. The demo swaps the database underneath it and nothing else.',
  ]),
  note('A demo that hides behind a booking form is a demo somebody has decided you should not see. Hand a '
     + 'principal the laptop and stop talking.'),
);

// ---------------------------------------------------------------- build
const doc = new Document({
  creator: 'LogicClass',
  title: 'LogicClass - Feature Guide',
  description: 'Every screen and every button, portal by portal.',
  numbering: {
    config: [{
      reference: 'dots',
      levels: [{
        level: 0, format: LevelFormat.BULLET, text: '•',
        alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 360, hanging: 220 } } },
      }],
    }],
  },
  styles: {
    default: { document: { run: { font: 'Calibri', size: 21, color: '2B3350' } } },
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 },
      },
    },
    children: kids,
  }],
});

Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync(out('LogicClass-Feature-Guide.docx'), b);
  console.log('written', b.length);
});
