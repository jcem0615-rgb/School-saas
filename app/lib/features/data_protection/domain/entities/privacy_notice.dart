/// What this system holds about a person, why, and who can see it.
///
/// Written as data rather than as a wall of prose in a widget, so the
/// same words render on screen, print to PDF, and can be diffed when
/// they change. A notice nobody can diff is a notice nobody can tell has
/// changed, and the whole point of versioning it is that a person who
/// acknowledged version 1 is asked again when version 2 says something
/// different.
///
/// This describes what the software does. It is not the school's own
/// privacy policy and does not try to be: the school is the one that
/// decides what it collects and why, and their notice will say things
/// about paper records and CCTV that this knows nothing about. What this
/// gives them is an accurate account of the part that lives in here,
/// which is the part they would otherwise have to reverse-engineer.
class PrivacyNotice {
  /// Bumped only when the substance changes -- a category added, a
  /// recipient added, a retention period changed. Fixing a typo does not
  /// re-prompt eight hundred families.
  static const int version = 1;

  static const String title = 'How this system handles personal data';

  static const String preamble =
      'Your school decides what information it keeps about you and why. '
      'This software is the place a lot of it is kept, so this page sets '
      'out exactly what is stored in it, who inside the school can see '
      'each part, and how long it stays. Your school will have its own '
      'privacy notice covering everything else it holds, including '
      'paper records.';

  static const List<PrivacyCategory> categories = [
    PrivacyCategory(
      name: 'Identity and enrolment',
      holds: 'Name, student or employee number, date of birth if the school '
          'records one, division, grade level and section, programme or '
          'strand, enrolment status and date, and an ID photograph.',
      why: 'To keep a class roll, to issue an ID card, and to produce the '
          'records a school is required to keep about who was enrolled.',
      seenBy: 'The office (Registrar, Admin, Director, Principal), the '
          'student themself, and a parent linked to that student. Teachers '
          'see the students in the divisions they are scoped to.',
    ),
    PrivacyCategory(
      name: 'Guardian and emergency contacts',
      holds: 'The name, relationship, phone number and, where given, the '
          'email address of each guardian recorded for a student.',
      why: 'So the school can reach somebody when a student is unwell, '
          'absent, or has raised an emergency alert.',
      seenBy: 'The office and the student\'s own record. These are shown to '
          'staff responding to an emergency alert.',
    ),
    PrivacyCategory(
      name: 'Attendance',
      holds: 'The date and time of each scan, whether it was recorded as '
          'present, late, absent or excused, and -- where the device '
          'reported one -- the location of the scan.',
      why: 'To keep the attendance record a school is required to keep, and '
          'to let a parent see whether their child arrived.',
      seenBy: 'The office and teaching staff, the student themself, and a '
          'linked parent.',
    ),
    PrivacyCategory(
      name: 'Academic records',
      holds: 'Marks against coursework and terms, submitted work and any '
          'files attached to it, and the computed averages that appear on '
          'a transcript or Form 137.',
      why: 'To report a student\'s progress to them and to their family, and '
          'to produce the academic records a school issues.',
      seenBy: 'The teacher who recorded the mark, the office, the student, '
          'and a linked parent.',
    ),
    PrivacyCategory(
      name: 'Fees and payments',
      holds: 'What has been assessed to a student, what has been paid, '
          'receipts, refunds, the running balance, and any payment claim '
          'filed online together with its reference number and proof image.',
      why: 'To bill accurately, to give a family a statement they can check, '
          'and to keep the school\'s own financial records.',
      seenBy: 'The office roles that handle money (Director, Admin, '
          'Registrar), the student, and a linked parent.',
    ),
    PrivacyCategory(
      name: 'Emergency alerts',
      holds: 'That an alert was raised, when, any message typed with it, '
          'and the device location at the time if the device gave one.',
      why: 'So that the student\'s class adviser and the school office can '
          'find and help them.',
      seenBy: 'The office and the student\'s class adviser. Linked parents '
          'see alerts raised by their own child.',
    ),
    PrivacyCategory(
      name: 'Guidance records',
      holds: 'Notes written by the guidance office about a meeting, a '
          'referral or an incident, and any summons issued.',
      why: 'To support a student and to keep a record of what the school '
          'did about a concern.',
      // The tightest circle in the system, and deliberately so.
      seenBy: 'The guidance office and the Director. These are not visible '
          'to teachers, to other office staff, or in the student portal.',
    ),
    PrivacyCategory(
      name: 'Account and activity',
      holds: 'Email address, role, the device token used to send push '
          'notifications, and an audit record of actions taken in the '
          'system -- who changed what, and when.',
      why: 'To sign you in, to notify you, and so that a change to a record '
          'can be traced to the person who made it.',
      seenBy: 'You can see your own activity. The Director and Admin can see '
          'the school-wide audit trail.',
    ),
  ];

  static const List<PrivacyPoint> rights = [
    PrivacyPoint(
      heading: 'Ask what is held about you',
      body: 'The school will give you a copy of what this system holds about '
          'you or your child. Ask the office, or raise a request from your '
          'own profile in the app.',
    ),
    PrivacyPoint(
      heading: 'Ask for a correction',
      body: 'If something is wrong -- a misspelled name, a wrong birth date, '
          'a mark entered against the wrong student -- ask the office to fix '
          'it. Corrections are recorded, so the change itself is traceable.',
    ),
    PrivacyPoint(
      heading: 'Ask for erasure, and be told when it cannot be done',
      body: 'You can ask for information to be deleted. A school cannot '
          'always agree: some records it is required to keep, and a '
          'financial record that has already been reported cannot simply '
          'vanish. If a request is refused you will be told which records '
          'and why.',
    ),
    PrivacyPoint(
      heading: 'Object, or complain',
      body: 'You can object to how your information is used, and you can '
          'complain to the school\'s Data Protection Officer. If you are not '
          'satisfied, you can take a complaint further to the regulator.',
    ),
  ];

  static const String retention =
      'Academic records are kept permanently -- a transcript issued twenty '
      'years after graduation is the point of them. Financial records are '
      'kept for as long as the school\'s own accounting rules require. '
      'Attendance, guidance notes and emergency alerts are kept while the '
      'student is enrolled and for the period the school sets after that. '
      'Push notification tokens are removed when you sign out. Your school '
      'sets the exact periods; ask its Data Protection Officer.';

  static const String security =
      'Access is decided by your role and enforced by the database itself, '
      'not only by what the app shows you -- so a screen you cannot reach is '
      'also data you cannot fetch. Balances, receipts, assessments and audit '
      'entries can only be written by the server, never directly by a '
      'device. Every change to a record is written to an audit trail.';

  /// Said plainly rather than buried: a school evaluating this will ask,
  /// and the honest answer is short.
  static const String sharing =
      'Nothing here is sold, and nothing is shared for advertising. '
      'Information leaves the school only where the school itself sends it '
      '-- to a government office that requires a report, for instance -- or '
      'through the cloud services that run this software on the school\'s '
      'behalf.';
}

class PrivacyCategory {
  final String name;
  final String holds;
  final String why;
  final String seenBy;

  const PrivacyCategory({
    required this.name,
    required this.holds,
    required this.why,
    required this.seenBy,
  });
}

class PrivacyPoint {
  final String heading;
  final String body;
  const PrivacyPoint({required this.heading, required this.body});
}
