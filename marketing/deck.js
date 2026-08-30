const pptxgen = require('pptxgenjs');
const { C, F, W, H, M, CW, bg, heading, cardGrid, rowList, callout, shadow, icon } = require('./lib');

const path = require('path');

// Resolved against this file rather than the shell's working
// directory, for the same reason guide.js does it.
const out = (f) => path.join(__dirname, f);

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE';
pres.author = 'LogicClass';
pres.title = 'LogicClass - School Management System';

const S = () => pres.addSlide();

(async () => {

// ---------------------------------------------------------------- 1. Title
{
  const s = S(); bg(s, C.deep);
  s.addShape('ellipse', { x: 9.6, y: -1.9, w: 6.2, h: 6.2, fill: { color: C.ink }, line: { width: 0 } });
  s.addShape('ellipse', { x: 11.3, y: 4.6, w: 3.4, h: 3.4, fill: { color: '25306B' }, line: { width: 0 } });
  s.addText('LogicClass', {
    x: M, y: 2.05, w: 8.4, h: 1.15, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 60, bold: true, color: C.paper,
  });
  s.addText('One system for the whole school day', {
    x: M, y: 3.2, w: 8.4, h: 0.5, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 22, color: C.accent, italic: true,
  });
  s.addText(
    'Enrolment, attendance, grades, fees, records, schedules, reports and safety - '
    + 'in one app your Director, Principal, Admin, Registrar, Faculty, Guidance, Staff, '
    + 'Students and Parents each sign in to and see only their own part of.',
    { x: M, y: 3.85, w: 8.1, h: 1.1, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 14.5, color: C.mist, lineSpacing: 22 });
  const chips = ['9 role portals', 'Android . Windows . Web', 'Data Privacy Act ready'];
  for (let i = 0; i < chips.length; i++) {
    const x = M + i * 2.75;
    s.addShape('roundRect', { x, y: 5.35, w: 2.55, h: 0.52, rectRadius: 0.26,
      fill: { color: C.ink }, line: { color: '3A4783', width: 1 } });
    s.addText(chips[i], { x, y: 5.35, w: 2.55, h: 0.52, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 12, bold: true, color: C.mist, align: 'center', valign: 'middle' });
  }
  s.addText('A demo walkthrough for schools', { x: M, y: 6.45, w: 8, h: 0.3, isTextBox: true, margin: 0,
    fontFace: F.body, fontSize: 11.5, color: '8895C4', charSpacing: 1.5 });
  s.addNotes('Open here. Say what LogicClass is in one line, then move straight to the school day it replaces.');
}

// ---------------------------------------------------------------- 2. Problem
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Why schools ask for this', 'The paperwork a school day leaves behind',
    { lede: 'Every item below is somebody in the school building copying the same fact into a second place.' });
  await cardGrid(s, [
    { icon: 'FiBookOpen', h: 'Records in five books', b: 'The class record, the registrar\'s ledger, the cashier\'s receipt book, the guidance file and the adviser\'s notebook - each holding part of one student.' },
    { icon: 'FiClock', h: 'Attendance copied twice', b: 'Called in the morning, written on a slip, then typed into a spreadsheet at the end of the week - if anyone gets to it.' },
    { icon: 'FiDollarSign', h: 'Balances nobody agrees on', b: 'The cashier has one figure, the parent remembers another, and the only way to settle it is to find the receipts.' },
    { icon: 'FiFileText', h: 'Form 137 takes days', b: 'A request comes in, somebody pulls the folder, copies the grades by hand, and nothing records that it was released.' },
    { icon: 'FiPhone', h: 'Parents told last', b: 'A fever, a suspension, a summons to the guidance office - the family finds out when the child gets home.' },
    { icon: 'FiSearch', h: 'No way to answer "who changed this?"', b: 'A grade moves, a balance is edited, a record disappears. Nothing in the school can say who, or when.' },
  ], { cols: 3, y: 2.05, h: 2.35 });
  s.addNotes('Keep this short. The audience already lives this; you are showing that you know it.');
}

// ---------------------------------------------------------------- 3. Portals
{
  const s = S(); bg(s, C.deep);
  heading(s, 'How it is organised', 'Nine portals, one school, one login each',
    { dark: true, lede: 'Sign in once and the app opens on the portal for your role. Nobody chooses a mode, and nobody sees a screen that is not theirs.' });
  await rowList(s, [
    { icon: 'FiHome', h: 'Director', b: 'School-wide oversight, approvals, money and audit' },
    { icon: 'FiAward', h: 'Principal', b: 'Academic leadership for one division' },
    { icon: 'FiSettings', h: 'Admin', b: 'People, branding, catalogues, schedules, reports' },
    { icon: 'FiUserCheck', h: 'Registrar / Cashier', b: 'Enrolment, records, fees, receipts, forms' },
    { icon: 'FiEdit3', h: 'Faculty', b: 'Coursework, grades, attendance, materials' },
    { icon: 'FiHeart', h: 'Guidance', b: 'Counselling records and student summons' },
    { icon: 'FiClipboard', h: 'Staff', b: 'Daily checklist, work log, material requests' },
    { icon: 'FiUser', h: 'Student', b: 'Subjects, timetable, marks, balance, ID' },
    { icon: 'FiUsers', h: 'Parent', b: 'Every linked child in one place' },
  ], { cols: 3, y: 2.5, rh: 1.3, gap: 0.4, disc: '2E3A70', glyph: C.accent,
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addText('Each account sees one portal. No shared screen, no shared password, no "admin mode".', {
    x: M, y: 6.5, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.accent });
  s.addNotes('Point out that the parent and student portals exist from day one - this is not a back-office-only system.');
}

// ---------------------------------------------------------------- 4. Director
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Director Portal', 'Every button on the Director\'s screen',
    { lede: 'Opens on four live figures for today: attendance rate, collections, pending approvals and upcoming meetings.' });
  await rowList(s, [
    { icon: 'FiSpeaker' in require('react-icons/fi') ? 'FiSpeaker' : 'FiBell', h: 'Announcements', b: 'Post to everyone or pick the roles; pin one to the top' },
    { icon: 'FiCalendar', h: 'Meeting Scheduler', b: 'Title, description, location, start and end; cancel a meeting' },
    { icon: 'FiCheckSquare', h: 'Approvals', b: 'One inbox for every request in the school. Every decision records who made it, when, and what they were deciding' },
    { icon: 'FiGrid', h: 'Class Schedule', b: 'The week\'s timetable for every section, with clash detection' },
    { icon: 'FiCheckCircle', h: 'System Check', b: 'Seven readiness checks before a school goes live' },
    { icon: 'FiShield', h: 'Data Requests', b: 'What families have asked about their data, and what was answered' },
    { icon: 'FiBarChart2', h: 'Reports', b: 'Enrolment, collections, attendance and grades - on screen, to Excel, or printed' },
    { icon: 'FiTag', h: 'Fee Schedules', b: 'Define the fee sets the cashier assesses against' },
    { icon: 'FiCreditCard', h: 'Expenses', b: 'Record school spending by category, or import a spreadsheet of it' },
    { icon: 'FiPhone', h: 'Emergency Numbers', b: 'The list every phone in the school can dial from' },
    { icon: 'FiSearch', h: 'Audit Trail', b: 'Every change made in the school, filterable by module and date' },
    { icon: 'FiActivity', h: 'My Activity', b: 'The same trail, narrowed to what you did' },
  ], { cols: 2, y: 2.15, rh: 0.73 });
  s.addNotes('This is the slide that answers "can the head of school see everything?" - yes, including who changed what.');
}

// ---------------------------------------------------------------- 5. Principal
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Principal Portal', 'Academic leadership, scoped to one division',
    { lede: 'A Principal is set to Elementary, Junior High, Senior High or College - and the records they can open stop at that line. Oversight, not data entry: grades stay the teacher\'s, records stay the registrar\'s.' });
  await cardGrid(s, [
    { icon: 'FiUsers', h: 'Student Records', b: 'Read the roster and any record in their division - view only.' },
    { icon: 'FiGrid', h: 'Class Schedule', b: 'The week as it is actually timetabled, section by section.' },
    { icon: 'FiUserCheck', h: 'Teacher Assignment', b: 'Who teaches which subject in which section, and who advises it.' },
    { icon: 'FiAlertTriangle', h: 'Emergency Alerts', b: 'Live alerts raised in the school, with the power to resolve one.' },
    { icon: 'FiPhone', h: 'Emergency Numbers', b: 'The school\'s published numbers, one tap to dial.' },
    { icon: 'FiBell', h: 'Announcements', b: 'Post school or division messages under their own name.' },
    { icon: 'FiCalendar', h: 'Meeting Scheduler', b: 'Call a meeting and say who it is for.' },
    { icon: 'FiCheckSquare', h: 'Approvals', b: 'Decide the requests that reach a division head - and the decision is signed with their account.' },
  ], { cols: 4, y: 2.35, h: 2.14, vgap: 0.22 });
  s.addNotes('The division boundary is enforced in the database rules, not just hidden in the UI - worth saying out loud.');
}

// ---------------------------------------------------------------- 6. Admin (people)
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Admin Portal . 1 of 2', 'People, academics and the school\'s identity',
    { lede: 'The operator role: the person who keeps the school configured week to week.' });
  await rowList(s, [
    { icon: 'FiUsers', h: 'Employee Management', b: 'Create an account for any role, set department, position and division scope' },
    { icon: 'FiKey', h: 'Reset Password', b: 'Issue a temporary password; the employee is forced to change it at next sign-in' },
    { icon: 'FiUserCheck', h: 'Activate / Suspend', b: 'Switch an account off without deleting anything it wrote' },
    { icon: 'FiUpload', h: 'Import employees', b: 'Bring a staff list in from Excel or CSV, or export the one you have' },
    { icon: 'FiEdit3', h: 'Teacher Assignment', b: 'Subject, section, school year, and who is the class adviser' },
    { icon: 'FiLayers', h: 'Strands & Programs', b: 'The Senior High strands and the college degree programs students enrol into' },
    { icon: 'FiGrid', h: 'Class Schedule', b: 'Build the week: day, start, end, room - the app refuses a clash' },
    { icon: 'FiImage' in require('react-icons/fi') ? 'FiImage' : 'FiTag', h: 'School Branding', b: 'Logo, printed name, address, school year, principal and director signatures' },
  ], { cols: 2, y: 2.1, rh: 1.1 });
  s.addNotes('Branding is what makes the printed ID cards and the Form 137 look like the school\'s own paper.');
}

// ---------------------------------------------------------------- 7. Admin (ops)
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Admin Portal . 2 of 2', 'Money, safety, oversight and going live',
    { lede: 'The same account, on the other half of the dashboard.' });
  await rowList(s, [
    { icon: 'FiTag', h: 'Fee Schedules', b: 'Named fee sets per division, grade level and school year' },
    { icon: 'FiBarChart2', h: 'Reports', b: 'The four school reports, exportable and printable' },
    { icon: 'FiBell', h: 'Announcements', b: 'Post and pin school messages' },
    { icon: 'FiCamera', h: 'Scan Attendance', b: 'Open the camera and mark whoever is scanned, in or out' },
    { icon: 'FiAlertTriangle', h: 'Emergency Alerts', b: 'See and resolve alerts raised anywhere in the school' },
    { icon: 'FiPhone', h: 'Emergency Numbers', b: 'Publish the numbers every portal can dial' },
    { icon: 'FiShield', h: 'Data Requests', b: 'Answer a family asking what is held about their child' },
    { icon: 'FiSearch', h: 'Audit Trail', b: 'Filter every change by module, date and person' },
    { icon: 'FiCheckCircle', h: 'System Check', b: 'Prove the deployment works before the first school day' },
    { icon: 'FiUser', h: 'Profile', b: 'Your own details, QR ID, activity and notification switch' },
  ], { cols: 2, y: 2.05, rh: 0.86 });
  s.addNotes('Admin is the operator role - the person who keeps the school configured week to week.');
}

// ---------------------------------------------------------------- 8. Registrar
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Registrar & Cashier Portal', 'The counter a family actually walks up to',
    { lede: 'Four tiles on the dashboard, and everything else opens from a student\'s own record.' });
  await cardGrid(s, [
    { icon: 'FiUsers', h: 'Student Records', b: 'Search and filter the roster by division, register a new student, import or export the list, load more as you scroll.' },
    { icon: 'FiShield', h: 'Data Requests', b: 'The queue of families asking for access, correction, erasure or objection - each with a target answer date.' },
    { icon: 'FiFileText', h: 'Online Payments', b: 'The review queue: every GCash or bank transfer a family sent in, with the reference and the amount, to approve or reject.' },
    { icon: 'FiSettings', h: 'Payment Setup', b: 'The school\'s own account name, number, QR image and the instructions families read before they send anything.' },
  ], { cols: 4, y: 2.4, h: 3.25 });
  s.addText('Registration issues a sequential student number - S-2026-000001 - that no app can invent or reuse.', {
    x: M, y: 5.95, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.ink });
  s.addNotes('Registration issues a sequential student number the client cannot forge - S-2026-000001.');
}

// ---------------------------------------------------------------- 9. Student record
{
  const s = S(); bg(s, C.deep);
  heading(s, 'Inside one student record', 'Nine actions, one screen',
    { dark: true, lede: 'Open a student from the roster and everything the school does for that child is one tap away.' });
  await rowList(s, [
    { icon: 'FiEdit3', h: 'Edit', b: 'Name, grade level, section, status and guardian contacts' },
    { icon: 'FiCamera', h: 'Photo', b: 'Upload the picture that prints on the school ID' },
    { icon: 'FiTag', h: 'Assess Fees', b: 'Charge a fee schedule, or type an ad-hoc charge; void one that was wrong' },
    { icon: 'FiDollarSign', h: 'Record Payment', b: 'Cash, GCash or bank transfer, with a sequential receipt number and the balance in front of you' },
    { icon: 'FiCreditCard', h: 'Payment History', b: 'Every charge, payment and refund, and how the balance is made up' },
    { icon: 'FiPrinter', h: 'Records & Forms', b: 'Print the Transcript of Records or Form 137, and log the release' },
    { icon: 'FiClock', h: 'Attendance History', b: 'Every scan, in and out, with the status the server decided' },
    { icon: 'FiKey', h: 'Create Portal Account', b: 'Issue the student their own login - only when the school wants one' },
    { icon: 'FiRefreshCw', h: 'Set Balance', b: 'An opening balance for a student carried over from the old system' },
  ], { cols: 3, y: 2.5, rh: 1.3, gap: 0.4, disc: '2E3A70', glyph: C.accent,
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addText('The balance moves only inside a recorded payment or refund - never by an edit.', {
    x: M, y: 6.5, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.accent });
  s.addNotes('The balance is server-owned: only a recorded payment or refund moves it, never a stray edit.');
}

// ---------------------------------------------------------------- 10. Faculty
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Faculty Portal', 'What a teacher opens between classes',
    { lede: 'Seven tiles, and none of them ask a teacher to be an administrator first.' });
  await rowList(s, [
    { icon: 'FiCalendar', h: 'My Schedule', b: 'Your own week - what you teach, when, where, to whom' },
    { icon: 'FiBookOpen', h: 'Coursework', b: 'Lesson plans, lessons, assignments, projects, exams and quizzes in one list' },
    { icon: 'FiEdit3', h: 'Grade Submission', b: 'Pick subject and section, load the roster, enter scores against a maximum' },
    { icon: 'FiUpload', h: 'Import grades', b: 'Bring a term\'s marks in from a spreadsheet instead of typing them' },
    { icon: 'FiInbox', h: 'Material Requests', b: 'File what you need; it lands in the same approvals inbox the Director reads' },
    { icon: 'FiCamera', h: 'Scan Attendance', b: 'Mark your class present by scanning their IDs' },
    { icon: 'FiAlertTriangle', h: 'Emergency Alerts', b: 'Raise or read an alert without leaving the room' },
    { icon: 'FiBell', h: 'Announcements', b: 'Post to your own sections under your own name' },
  ], { cols: 2, y: 2.1, rh: 1.12 });
  s.addNotes('A grade can be corrected but never silently reassigned to a different student - the rule refuses it.');
}

// ---------------------------------------------------------------- 11. Coursework deep dive
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Coursework, answer keys and submissions', 'Set work, mark it, and let it mark itself',
    { lede: 'Six kinds of coursework share one screen: Lesson Plan, Lesson, Assignment, Project, Exam and Quiz.' });
  await cardGrid(s, [
    { icon: 'FiEdit3', h: 'Set the work', b: 'Type, title, description, subject, section, due date and total points. Leave "Publish now" off and it saves as a draft only staff can see.' },
    { icon: 'FiKey', h: 'Answer key', b: 'Write the correct answers one per line and set the marks per question. Save the key and everything already handed in is re-marked against it.' },
    { icon: 'FiCheckSquare', h: 'Submissions', b: 'Who handed in, who is outstanding, who was late. Open one, give it a score and written feedback, or let the key score it.' },
    { icon: 'FiSend', h: 'The student side', b: 'The student answers question by question, sees the mark and the teacher\'s feedback, and can change their answer while it is still open.' },
  ], { cols: 4, y: 2.4, h: 3.25 });
  s.addText('A draft stays invisible to students until the teacher publishes it.', {
    x: M, y: 5.95, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.ink });
  s.addNotes('Auto-marking is the demo moment: paste a key, watch the marks appear.');
}

// ---------------------------------------------------------------- 12. Guidance + Staff
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Guidance and Staff Portals', 'Two smaller roles, deliberately kept apart',
    { lede: 'One of these records is the most closely held in the system. The other is a work log nobody, including its author, can edit.' });
  await cardGrid(s, [
    { icon: 'FiHeart', h: 'Guidance Records', b: 'Counselling notes against one student, by category. The guidance office, the Director and the division Principal - and nobody else, not even the class adviser.' },
    { icon: 'FiMail', h: 'Student Summons', b: 'Call a student to the office with a reason and a time. Visible to the student and the linked parent too: a family should not learn about it afterwards.' },
    { icon: 'FiCheckSquare', h: 'Staff Checklist', b: 'A personal task list for today. Add a task, edit it, tick it off. It resets with the date rather than piling up week on week.' },
    { icon: 'FiClipboard', h: 'Daily Reports', b: 'A short end-of-day work log. Written once and never editable - a correction is a new entry, so the record stays trustworthy.' },
  ], { cols: 4, y: 2.35, h: 2.65 });
  await rowList(s, [
    { icon: 'FiInbox', h: 'Material Requests', b: 'Staff file into the same approvals inbox faculty use' },
    { icon: 'FiAlertTriangle', h: 'Emergency Alerts', b: 'Guidance sees every alert raised in the school' },
    { icon: 'FiCreditCard', h: 'My e-ID', b: 'Staff carry their own scannable ID for timekeeping' },
  ], { cols: 3, y: 5.45, rh: 0.7, gap: 0.35 });
  s.addNotes('The guidance-record privacy asymmetry is a question a school WILL ask. Answer it before they do.');
}

// ---------------------------------------------------------------- 13. Student
{
  const s = S(); bg(s, C.deep);
  heading(s, 'Student Portal', 'Ten things a student can check on their phone',
    { dark: true, lede: 'A school can issue logins to every student, to some, or to none - a student record does not need an account to exist.' });
  await rowList(s, [
    { icon: 'FiBookOpen', h: 'Subjects', b: 'Every subject, its teacher, and what has been posted in it' },
    { icon: 'FiCalendar', h: 'My Timetable', b: 'The week, day by day, with room and teacher' },
    { icon: 'FiFileText', h: 'Assignments & Exams', b: 'The feed of published work, filterable by kind' },
    { icon: 'FiAward', h: 'Grades', b: 'Marks per subject and term, as the teacher submitted them' },
    { icon: 'FiClock', h: 'Attendance', b: 'Their own record, every scan, in and out' },
    { icon: 'FiDollarSign', h: 'Payments & Balance', b: 'What was charged, what was paid, what is left - and how it adds up' },
    { icon: 'FiFileText', h: 'Promissory Note', b: 'Ask for an extension with an amount and a reason' },
    { icon: 'FiAlertTriangle', h: 'Emergency', b: 'One button that alerts the adviser and the parents' },
    { icon: 'FiBell', h: 'Announcements', b: 'Everything addressed to students' },
    { icon: 'FiCreditCard', h: 'My QR ID', b: 'The school ID card, on the phone and printable' },
  ], { cols: 2, y: 2.15, rh: 0.87, disc: '2E3A70', glyph: C.accent,
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addNotes('Students not issued a login still exist as records - the school decides who gets an account.');
}

// ---------------------------------------------------------------- 14. Parent
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Parent Portal', 'Every child in one place, without a second app',
    { lede: 'One account can be linked to several children. The dashboard is the list of them; opening one gives four tabs.' });
  await cardGrid(s, [
    { icon: 'FiClock', h: 'Attendance', b: 'Every day their child was scanned in, and whether it was on time.' },
    { icon: 'FiCalendar', h: 'Timetable', b: 'Where the child is meant to be, hour by hour.' },
    { icon: 'FiAward', h: 'Grades', b: 'Marks as the teacher submitted them, per subject and term.' },
    { icon: 'FiDollarSign', h: 'Statement of Account', b: 'Charges, payments and the balance - read only. Refunds stay with the school.' },
  ], { cols: 4, y: 2.5, h: 2.4 });
  await rowList(s, [
    { icon: 'FiAlertTriangle', h: 'Emergency Alerts', b: 'An unresolved alert about their child is shown as a banner, not hidden behind an icon' },
    { icon: 'FiBell', h: 'Announcements', b: 'Everything the school addressed to parents, pushed to the phone' },
    { icon: 'FiSend', h: 'Pay online', b: 'Send the fee by GCash or bank transfer and submit the reference for review' },
  ], { cols: 3, y: 5.45, rh: 0.7, gap: 0.35 });
  s.addNotes('The banner is deliberate: a push notification can be missed, so the app tells them anyway.');
}

// ---------------------------------------------------------------- 15. Attendance
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Attendance', 'A camera, a QR code, and no slips of paper',
    { lede: 'Every person in the school carries a QR ID. Staff roles carry a scanner. The scan itself decides the rest.' });
  await cardGrid(s, [
    { icon: 'FiCreditCard', h: 'The ID card', b: 'A real card layout with the school logo behind it, the student\'s photo, and the principal and director signatures from Branding. Print it, or keep it on the phone.' },
    { icon: 'FiCamera', h: 'The scan', b: 'Open Scan Attendance, point at the code, and the record is written. Scan again later and it is a time-out, not a duplicate.' },
    { icon: 'FiClock', h: 'Present or late', b: 'Decided on the server against the school\'s cutoff time and the school\'s timezone - not by the clock on the phone doing the scanning.' },
    { icon: 'FiEye', h: 'Who can see it', b: 'The student, their linked parent, and the staff roles allowed to. Attendance cannot be written from a client at all, only by the scan.' },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('The "server decides late" point kills the obvious cheat - changing the phone clock.');
}

// ---------------------------------------------------------------- 15b. Subject registers
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Attendance per subject', 'The register the teacher takes, not just the gate',
    { lede: 'The gate scan says they came to school. It cannot say they were in Physics - which is the question behind a grade that dropped.' });
  await cardGrid(s, [
    { icon: 'FiLogIn', h: 'Time in', b: 'The teacher presses it at the start of the class. The whole section appears, marked present - so a register taken in a hurry still records the truth about everyone who was there.' },
    { icon: 'FiUserCheck', h: 'Mark the exceptions', b: 'Present, late, absent, excused - one tap each. Three absences is three taps, not forty. Corrections allowed on the day, not after.' },
    { icon: 'FiLogOut', h: 'Time out', b: 'Ends the class, and records the finish time against everyone who was in it. Absent students get no time out, because they had no time in.' },
    { icon: 'FiTrendingDown', h: 'What the family sees', b: 'Every subject with its own attendance rate, worst first - because the reason anybody opens this screen is to find the one that is going wrong.' },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('This is the one a subject teacher asks for in the first ten minutes. Pair it with the grades screen.');
}

// ---------------------------------------------------------------- 16. Fees
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Fees and payments', 'From the fee schedule to a receipt in a parent\'s hand',
    { lede: 'Six steps, and the family can follow every one of them from their own account.' });
  await rowList(s, [
    { icon: 'FiTag', h: '1. Define the fee schedule', b: 'A named set of fees for a division, grade level and school year - tuition, miscellaneous, books, whatever the school charges' },
    { icon: 'FiCheckSquare', h: '2. Assess the student', b: 'Charge a schedule against one student, or type an ad-hoc charge line by line. The total is shown before anything is committed' },
    { icon: 'FiDollarSign', h: '3. Take the payment', b: 'Type the number on the ID card and the student\'s name, class and balance appear. Nothing sends until the ID names somebody' },
    { icon: 'FiRefreshCw', h: '4. Refund if needed', b: 'A refund is its own row against the original payment. Director and Admin only, enforced on the server' },
    { icon: 'FiPieChart', h: '5. Show the family the arithmetic', b: 'Charged, paid, and what is left - with the assessments listed, so a balance is never a number nobody can explain' },
    { icon: 'FiFileText', h: '6. Void a mistake, do not delete it', b: 'A wrong assessment is voided and stays visible. The history of a family\'s account is never quietly rewritten' },
  ], { cols: 2, y: 2.2, rh: 1.4 });
  s.addNotes('Six steps, one screen each. Walk it live if there is time.');
}

// ---------------------------------------------------------------- 17. Online payments
{
  const s = S(); bg(s, C.deep);
  heading(s, 'Online payments', 'GCash and bank transfers, reviewed before they count', { dark: true,
    lede: 'No gateway to sign up for and no percentage taken. The school publishes its own account, and a person approves what comes in.' });
  await cardGrid(s, [
    { icon: 'FiSettings', h: 'The school sets it up', b: 'Account name, number, a QR image families can scan, and the instructions they read first.' },
    { icon: 'FiSend', h: 'The family sends it', b: 'They pay by their own app, then submit the reference number, the amount and what it was for.' },
    { icon: 'FiCheckCircle', h: 'The cashier reviews', b: 'A queue of everything awaiting review. Approve and it becomes a real payment with a receipt; reject and the family is told.' },
    { icon: 'FiBell', h: 'The cashier is told', b: 'A new submission raises an alert wherever the cashier is in the app - not only on the review screen.' },
  ], { cols: 4, y: 2.55, h: 3.05, tint: C.ink, line: '3A4783', discColor: C.accent, glyph: '141B3D',
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addText('No merchant account to open, no gateway percentage, and no payment counted until a person says so.', {
    x: M, y: 6.05, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.accent });
  s.addNotes('This is a differentiator for smaller schools: no merchant account, no gateway fees.');
}

// ---------------------------------------------------------------- 17b. Messaging
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Parent and teacher, talking', 'One thread per child, and nobody else in it',
    { lede: 'A parent can message the teachers who teach their child. Not the whole staff list - the teachers who actually teach them.' });
  await cardGrid(s, [
    { icon: 'FiUsers', h: 'Who can reach whom', b: 'Worked out from the timetable, the section and the family link, every time a thread is opened. Nobody maintains a list, and nobody can message outside it.' },
    { icon: 'FiLock', h: 'Who can read it', b: 'The two of them. Not the Principal, not an administrator. A parent who believes the office is reading tells the teacher nothing worth reading.' },
    { icon: 'FiMessageSquare', h: 'One thread per child', b: 'A parent with two children taught by the same teacher gets two threads, so nobody has to say which child they mean.' },
    { icon: 'FiShield', h: 'What was said stays said', b: 'A message cannot be edited or unsent, and the sender is stamped by the server - nobody can post in the other person\'s name.' },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('The "not even the principal" point is the one that gets a reaction. It is also what makes the channel worth having.');
}

// ---------------------------------------------------------------- 17c. Staff time and leave
{
  const s = S(); bg(s, C.deep);
  heading(s, 'Staff time and leave', 'The month a payroll clerk reads', { dark: true,
    lede: 'The same scanner that marks students marks employees. This is where those scans become a month.' });
  await cardGrid(s, [
    { icon: 'FiCalendar', h: 'File it', b: 'Any employee files leave from their own screen. Working days are counted for them, weekends excluded, and the count is kept.', dark: true },
    { icon: 'FiCheckCircle', h: 'Decide it', b: 'One queue for the office, with the decided ones beneath it. Who decided, in what role, when, and why - and the employee is told.', dark: true },
    { icon: 'FiClock', h: 'The timesheet', b: 'Every day named as exactly one thing: worked, late, on leave, rest day, or absent. Approved leave is what turns a blank day from an absence into an authorised one.', dark: true },
    { icon: 'FiAlertCircle', h: 'Nothing is guessed', b: 'A day with a time in and no time out contributes no hours, and the sheet says how many such days there are. No invented hours reach a payslip.', dark: true },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('Say plainly that this is not payroll. It is the sheet payroll is run from.');
}

// ---------------------------------------------------------------- 17d. Notifications
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Nobody finds out too late', 'A push, and a record of it that is still there tomorrow',
    { lede: 'A push notification is gone the moment it is swiped away. Everything the school sends is also written to the person\'s own inbox.' });
  await rowList(s, [
    { icon: 'FiBell', h: 'An announcement', b: 'Reaches every account it is addressed to - and only those. Whose phone rings is decided on the server, not by a filter on a list' },
    { icon: 'FiUserX', h: 'A guidance summons', b: 'The student and every linked parent are told, and told again if the office calls it off. A family should not rearrange a day around an appointment that is not happening' },
    { icon: 'FiAlertTriangle', h: 'An emergency', b: 'The class adviser and the student\'s parents, at high priority, with the app closed' },
    { icon: 'FiCalendar', h: 'A leave decision', b: 'The employee who filed it. Somebody who never hears back either comes in when they should not have, or stays away when they were expected' },
    { icon: 'FiMessageCircle', h: 'A message', b: 'The other person in the conversation, named by the child it is about' },
    { icon: 'FiInbox', h: 'And all of it, in one inbox', b: 'Reached from the bell in every portal. A phone that was off, or a browser that never granted permission, misses nothing' },
  ], { cols: 2, y: 2.2, rh: 1.4 });
  s.addNotes('The inbox is the part competitors skip. Push alone means the school cannot prove it told anybody.');
}

// ---------------------------------------------------------------- 18. Records & forms
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Records and forms', 'The Transcript and Form 137, printed and logged',
    { lede: 'The two documents a school is asked for most, generated from the records already in the system.' });
  await cardGrid(s, [
    { icon: 'FiPrinter', h: 'Print it', b: 'The Transcript of Records or Form 137, laid out on the school\'s own letterhead with its logo, address, school year and the principal and director signatures.' },
    { icon: 'FiFileText', h: 'Say why', b: 'Purpose, who it was released to, their relationship to the student, and any remarks - captured at the moment of release, not remembered later.' },
    { icon: 'FiSearch', h: 'Keep the history', b: 'Every release is listed with its date and copy count. When the receiving school writes back asking when Form 137 was sent, the answer is on the screen.' },
    { icon: 'FiRefreshCw', h: 'Print again', b: 'A reprint is recorded as a reprint. The count of copies in circulation stays honest.' },
  ], { cols: 4, y: 2.4, h: 3.25 });
  s.addText('Nothing is copied out by hand, so nothing is copied out wrong.', {
    x: M, y: 5.95, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.ink });
  s.addNotes('The release log is the part registrars react to - it is the question they get asked years later.');
}

// ---------------------------------------------------------------- 19. Schedule
{
  const s = S(); bg(s, C.paper);
  heading(s, 'The class schedule', 'One room, one teacher, one section, one slot',
    { lede: 'Build the week block by block: subject, section, teacher, room, day, start and end.' });
  await cardGrid(s, [
    { icon: 'FiAlertTriangle', h: 'Clashes are refused', b: 'Two classes in the same room, the same teacher in two places, or one section double-booked - the app names the conflict and will not save it. Checked again on the server before it is written.' },
    { icon: 'FiClock', h: 'Times the way people type them', b: '7:30 AM, 7:30am, 07:30, 0730 - all understood. Nobody should have to learn a time format to build a timetable.' },
    { icon: 'FiPrinter', h: 'Printed as a grid', b: 'The week as a wall chart, with the section or the teacher dropped from the cells when it is the same all the way down.' },
    { icon: 'FiUser', h: 'Everyone sees their own', b: 'The teacher gets their week, the student gets theirs, the parent gets their child\'s - all from the same blocks.' },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('Ask the school for their worst timetable clash story, then show it being refused.');
}

// ---------------------------------------------------------------- 20. Reports
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Reports', 'The four numbers a school is actually asked for',
    { lede: 'Choose a period - this school year, this month, the last 30 days - and read it on screen, export it to Excel, or print it.' });
  await cardGrid(s, [
    { icon: 'FiUsers', h: 'Enrolment by division', b: 'Head count by division and grade level, every status shown - not just the enrolled ones.' },
    { icon: 'FiDollarSign', h: 'Collections and receivables', b: 'What was charged, what came in, and what is still owed.' },
    { icon: 'FiClock', h: 'Attendance rate by section', b: 'Present, late and absent by section, with the rate. Excused days sit outside the rate.' },
    { icon: 'FiBarChart2', h: 'Grade distribution', b: 'Marks banded against the DepEd descriptors, per subject.' },
  ], { cols: 4, y: 2.45, h: 2.55 });
  await rowList(s, [
    { icon: 'FiDownload', h: 'Export to Excel', b: 'The same table, as a spreadsheet you can rework' },
    { icon: 'FiPrinter', h: 'Print', b: 'A PDF with the school\'s heading and the totals row shaded' },
  ], { cols: 2, y: 5.5, rh: 0.7, gap: 0.5 });
  s.addNotes('Enrolment ignores the date range on purpose - it is a head count, not a period figure.');
}

// ---------------------------------------------------------------- 21. Emergency
{
  const s = S(); bg(s, C.deep);
  heading(s, 'When something goes wrong', 'One button, and the right people know',
    { dark: true, lede: 'Raised from a student\'s phone, seen by the staff who can act, and told to the family the same minute.' });
  await cardGrid(s, [
    { icon: 'FiAlertTriangle', h: 'Raise it', b: 'A student presses one button and says what happened. Their adviser and their parents are notified.' },
    { icon: 'FiEye', h: 'See it', b: 'Faculty, Guidance, Principal, Admin and the Director see live alerts, and any of them can resolve one.' },
    { icon: 'FiBell', h: 'Tell the family', b: 'The parent gets a push, and a banner on their dashboard in case the push never arrived.' },
    { icon: 'FiPhone', h: 'Dial out', b: 'The school\'s published numbers - clinic, guard, barangay, hospital - one tap from any portal.' },
  ], { cols: 4, y: 2.4, h: 3.0, tint: C.ink, line: '3A4783', discColor: C.accent, glyph: '141B3D',
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addText('Every alert is logged with who raised it, when, and who resolved it.', {
    x: M, y: 5.85, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 16, italic: true, color: C.accent });
  s.addNotes('Keep this slide slow. It is the one that gets remembered.');
}

// ---------------------------------------------------------------- 22. Import/export
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Moving in from what you have now', 'Excel in, Excel out - on five different lists',
    { lede: 'A school changing systems has years of data in spreadsheets. It does not get retyped.' });
  await rowList(s, [
    { icon: 'FiUsers', h: 'Students', b: 'The whole roster, with divisions, sections and guardians' },
    { icon: 'FiUserCheck', h: 'Employees', b: 'Staff with department, position and division scope' },
    { icon: 'FiAward', h: 'Grades', b: 'A term\'s marks, per subject and section' },
    { icon: 'FiCreditCard', h: 'Expenses', b: 'The school\'s spending, by category and date' },
    { icon: 'FiEdit3', h: 'Teacher assignments', b: 'Who teaches what, to whom, this year' },
    { icon: 'FiDownload', h: 'Blank template', b: 'Download the exact .xlsx shape the import expects' },
  ], { cols: 3, y: 2.4, rh: 1.35, gap: 0.35 });
  await callout(s, 'FiEye',
    'Every import shows you what it read before it writes anything, and every export comes back as .xlsx or .csv.',
    { y: 5.45 });
  s.addNotes('The blank template removes the "what columns do you want?" phone call.');
}

// ---------------------------------------------------------------- 23. Security
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Security', 'Not hidden in the app - refused by the database',
    { lede: 'Every rule below is enforced where the data lives, so it holds even if somebody bypasses the app entirely.' });
  await cardGrid(s, [
    { icon: 'FiLock', h: 'One school cannot see another', b: 'Every record lives under its own school, and an account carries the school it belongs to. There is no query that crosses the line.' },
    { icon: 'FiLayers', h: 'Divisions hold too', b: 'A Junior High teacher scoped to their division cannot open a Senior High record - the read is denied, not filtered.' },
    { icon: 'FiShield', h: 'Sensitive fields are server-owned', b: 'A balance moves only inside a recorded payment. A role, a status or a student number cannot be changed by an app at all.' },
    { icon: 'FiSearch', h: 'Everything is written down', b: 'Every create, edit and delete lands in the audit trail with who did it and when, automatically. A decision on a request is signed with the account that made it, so an approval cannot be attributed to somebody else.' },
  ], { cols: 2, y: 2.35, h: 2.3 });
  s.addNotes('If they have an IT person in the room, this is the slide they will ask about.');
}

// ---------------------------------------------------------------- 24. Privacy
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Data Privacy Act', 'What to hand your Data Protection Officer',
    { lede: 'Schools hold minors\' records. The questions a DPO asks are answered inside the app, not in a promise.' });
  await rowList(s, [
    { icon: 'FiFileText', h: 'A privacy notice in the app', b: 'Eight categories of data, what is held, why, and who sees it' },
    { icon: 'FiCheckCircle', h: 'A recorded acknowledgement', b: 'Every account reads it before their first use, and the version they read is stored' },
    { icon: 'FiSearch', h: 'Access requests', b: 'A family can ask what is held about their child, from their own profile' },
    { icon: 'FiEdit3', h: 'Correction and objection', b: 'The other rights the Act names, filed the same way' },
    { icon: 'FiArchive', h: 'A retention schedule', b: 'How long each kind of record is kept, written down' },
    { icon: 'FiClock', h: 'A clock on every request', b: 'Each one carries a target answer date and shows when it is overdue' },
  ], { cols: 3, y: 2.4, rh: 1.35, gap: 0.35 });
  await callout(s, 'FiFileText',
    'A Data Processing Agreement template ships with the system, ready for your DPO to review.',
    { y: 5.45 });
  s.addNotes('Most competitors cannot answer this. Lead with it if the DPO is in the room.');
}

// ---------------------------------------------------------------- 25. Platforms
{
  const s = S(); bg(s, C.deep);
  heading(s, 'Where it runs', 'The same app, on whatever the school already has',
    { dark: true, lede: 'One codebase, three builds. No separate teacher app, no separate parent app.' });
  await cardGrid(s, [
    { icon: 'FiSmartphone', h: 'Android', b: 'Installed from an APK the school hands out itself. Camera scanning and push notifications, on the phones staff already carry.' },
    { icon: 'FiMonitor', h: 'Windows', b: 'A desktop build for the registrar\'s and cashier\'s counter, where the printing and the typing happen.' },
    { icon: 'FiGlobe', h: 'Web', b: 'Any browser, and installable to the home screen as a PWA - including iPhone, once added to the Home Screen.' },
    { icon: 'FiBell', h: 'Notifications', b: 'An announcement reaches the phones of the roles it was addressed to, even with the app closed.' },
  ], { cols: 4, y: 2.5, h: 3.15, tint: C.ink, line: '3A4783', discColor: C.accent, glyph: '141B3D',
       headColor: C.paper, bodyColor: '9EABD6' });
  s.addText('One codebase means a fix reaches the registrar\'s desktop and the parent\'s phone together.', {
    x: M, y: 6.0, w: CW, h: 0.4, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: C.accent });
  s.addNotes('No app store account needed on the school side for Android - the APK is handed over directly.');
}

// ---------------------------------------------------------------- 26. Go live
{
  const s = S(); bg(s, C.paper);
  heading(s, 'Going live', 'Seven checks that go green before the first school day',
    { lede: 'Built because the worst time to find a misconfiguration is on the morning a school starts using the system.' });
  await rowList(s, [
    { icon: 'FiDatabase' in require('react-icons/fi') ? 'FiDatabase' : 'FiLayers', h: 'Database reachable', b: 'A real read from the school\'s own records returns' },
    { icon: 'FiShield', h: 'Security rules deployed', b: 'A write the rules must refuse IS refused - the check that matters most' },
    { icon: 'FiZap', h: 'Server functions deployed', b: 'Every callable answers, in the right region' },
    { icon: 'FiSearch', h: 'Database indexes created', b: 'The queries the app depends on actually run' },
    { icon: 'FiUpload', h: 'File storage writable', b: 'A probe file is written and removed again' },
    { icon: 'FiKey', h: 'Account claims set', b: 'The signed-in account carries its role and its school' },
    { icon: 'FiTag', h: 'School details filled in', b: 'Name, logo, year, principal and DPO - a warning, not a failure' },
  ], { cols: 2, y: 2.25, rh: 0.98 });
  await callout(s, 'FiShield',
    'A database left in test mode behaves perfectly - right up to the day one school reads another\'s records. This is the check that catches it.',
    { y: 6.15, h: 0.85 });
  s.addNotes('A test-mode database looks perfect until the day one school reads another\'s records. This catches it.');
}

// ---------------------------------------------------------------- 27. Close
{
  const s = S(); bg(s, C.deep);
  s.addShape('ellipse', { x: -2.2, y: 3.4, w: 6.6, h: 6.6, fill: { color: C.ink }, line: { width: 0 } });
  s.addText('See it with your own school\'s data', {
    x: 5.0, y: 2.15, w: 7.6, h: 1.5, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 40, bold: true, color: C.paper, lineSpacing: 46 });
  s.addText(
    'Bring one section\'s roster, one term of grades and last month\'s collections. '
    + 'We load them in front of you, and you click through the portals your own staff would use.',
    { x: 5.0, y: 3.75, w: 7.4, h: 1.1, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 14.5, color: C.mist, lineSpacing: 23 });
  s.addText('LogicClass', { x: 5.0, y: 5.35, w: 7.4, h: 0.5, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 24, bold: true, color: C.accent });
  s.addNotes('Close by asking for their data. A demo on their own roster sells itself.');
}

await pres.writeFile({ fileName: out('LogicClass-Demo.pptx') });
console.log('written');
})();
