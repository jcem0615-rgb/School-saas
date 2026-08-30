const fs = require('fs');
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
  '22. Security',
  '23. Data Privacy Act',
  '24. Where it runs',
  '25. Going live',
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
    ['Admin', 'School operations', 'Employee accounts, teacher assignment, strands and programs, branding, schedules, fee schedules, reports, audit trail, attendance scanning.'],
    ['Registrar / Cashier', 'The front counter', 'Enrolment, student records, fee assessment, payments and receipts, printed forms, online-payment review and setup, data requests.'],
    ['Faculty', 'Teaching', 'Own timetable, coursework, answer keys, submissions, grade submission, material requests, attendance scanning, announcements.'],
    ['Guidance', 'Student welfare', 'Guidance records, student summons, emergency alerts.'],
    ['Staff', 'Non-teaching staff', 'Daily checklist, daily work reports, material requests, own scannable ID.'],
    ['Student', 'The learner', 'Subjects, timetable, coursework, grades, attendance, balance, promissory note, emergency button, announcements, QR ID.'],
    ['Parent', 'The family', 'Each linked child\'s attendance, timetable, grades and statement of account; emergency alerts; announcements; online payment.'],
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
    ['First use', 'Before you start', 'The privacy notice. It must be read to the end before the button to continue becomes available; the version read is recorded against the account.'],
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
);

// ---------------------------------------------------------------- 22 Security
add(
  H1('22. Security'),
  P('Every rule below is enforced where the data lives rather than in the app, so it holds even for a '
    + 'request that never went through the app at all.'),
  H2('22.1 One school cannot see another'),
  P('Every record lives under its own school, and every account carries the school it belongs to. There is '
    + 'no query that crosses that line, for any role.'),
  H2('22.2 Divisions hold too'),
  P('A Principal, Registrar, Faculty member or Guidance counsellor can be scoped to Elementary, Junior '
    + 'High, Senior High or College - and, for College, to a department. A Junior High teacher scoped to '
    + 'their division cannot open a Senior High record: the read is denied, not filtered out of a list.'),
  H2('22.3 Fields the app can never write'),
  featureTable([
    ['balance', 'Only a recorded payment, refund or assessment', 'A balance that could be typed is a balance nobody can trust.'],
    ['studentNumber', 'Only registration', 'A permanent identifier, issued once.'],
    ['role, status, schoolId', 'Only the dedicated actions that audit them', 'A role change is a security event and is recorded as one.'],
    ['attendance', 'Only a scan', 'Cross-user writes are not something a client should be trusted with.'],
    ['receipt numbers', 'Only the server', 'Two cashiers at once must not be able to issue the same number.'],
  ], ['Field or record', 'Written by', 'Why']),
  H2('22.4 Everything is written down'),
  P('Every create, edit and delete in the school lands in the audit trail with who did it and when, and it '
    + 'is recorded automatically rather than because a screen remembered to log it. The Director and Admin '
    + 'read the whole trail, filtered by module and date range; every account can read its own.'),
);

// ---------------------------------------------------------------- 23 Privacy
add(
  H1('23. Data Privacy Act'),
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

// ---------------------------------------------------------------- 24 Platforms
add(
  H1('24. Where it runs'),
  featureTable([
    ['Android', 'An APK the school distributes', 'Camera scanning and push notifications, on the phones staff already carry. No app store account is needed on the school side.'],
    ['Windows', 'A desktop build', 'For the registrar\'s and cashier\'s counter, where the printing and the typing happen.'],
    ['Web', 'Any browser', 'Installable to the home screen as a progressive web app, including on iPhone once added to the Home Screen.'],
  ], ['Platform', 'How it is delivered', 'Notes']),
  P('It is one codebase and three builds, not three products - so a fix reaches the registrar\'s desktop '
    + 'and the parent\'s phone together, and there is no separate teacher app or parent app to keep in step.'),
);

// ---------------------------------------------------------------- 25 Going live
add(
  H1('25. Going live'),
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
  fs.writeFileSync('LogicClass-Feature-Guide.docx', b);
  console.log('written', b.length);
});
