/// The agreement every account accepts before its first use.
///
/// Written as data rather than prose inside a widget, for the same reason
/// the privacy notice is: the same words render on screen and can be
/// diffed when they change, and somebody who accepted version 1 is asked
/// again when version 2 says something different. Terms nobody can diff
/// are terms nobody can tell have changed.
///
/// **This is a template, not legal advice.** It describes honestly what
/// the software does and what it asks of the person using it, which is
/// the part a school would otherwise have to reverse-engineer. The
/// school's own counsel should read it before a single account is issued,
/// the same way `legal/data-processing-agreement.md` is a starting point
/// rather than a signed document. Anywhere it makes a commitment the
/// school cannot keep -- an availability figure, a support response time
/// -- that is the school's to change, and it is deliberately silent on
/// both rather than inventing numbers.
class TermsOfService {
  /// Bumped only when the substance changes. A typo fix does not put a
  /// gate in front of eight hundred families.
  static const int version = 1;

  static const String title = 'Terms of use';

  static const String preamble =
      'This account was issued to you by your school. These terms cover '
      'what you may use it for and what is expected of you while you do. '
      'They are between you and your school -- the school decides who '
      'gets an account, what is recorded in it, and when it is closed.';

  static const List<TermsClause> clauses = [
    TermsClause(
      heading: 'The account is yours alone',
      body:
          'Your sign-in belongs to you and is not to be shared, lent or '
          'left signed in on a machine somebody else uses. Anything done '
          'with your account is recorded against your name, and the '
          'school will treat it as yours. If you think somebody else has '
          'your password, change it and tell the office the same day.',
    ),
    TermsClause(
      heading: 'What you see is what you were given',
      body:
          'Each account is scoped to a role, and some are scoped further '
          'to one division. Do not attempt to reach records outside that '
          'scope, whether through the app or around it. The system '
          'refuses those requests, and it records that they were made.',
    ),
    TermsClause(
      heading: 'Other people\'s information',
      body:
          'Much of what you can see here is somebody else\'s personal '
          'information -- a student\'s marks, a family\'s balance, a '
          'counselling note. Use it for your work at the school and '
          'nothing else. Do not copy it out, photograph it, or repeat it '
          'to anybody who would not have been given access themselves.',
    ),
    TermsClause(
      heading: 'Records you enter',
      body:
          'Enter what is true and correct what is not. A mark, a payment '
          'or an attendance record entered carelessly follows a student '
          'for years. Where the system will not let you delete something '
          '-- a work log, a released document, a voided assessment -- '
          'that is deliberate: the correction is a new entry, not a '
          'quiet edit of the old one.',
    ),
    TermsClause(
      heading: 'The school\'s data is the school\'s',
      body:
          'Everything recorded here belongs to the school, not to the '
          'software. The school can export it, and can ask for it to be '
          'returned or destroyed when it stops using the system. Nothing '
          'in it is sold, and it is not used to advertise anything.',
    ),
    TermsClause(
      heading: 'Availability',
      body:
          'The system runs on hosted infrastructure and can be '
          'unavailable -- for maintenance, or because something upstream '
          'has failed. Keep working the way your school tells you to when '
          'that happens; do not treat an outage as a reason to stop '
          'recording something that happened.',
    ),
    TermsClause(
      heading: 'When these terms change',
      body:
          'A change to the substance of this page raises its version, and '
          'you will be asked to read and accept it again before you can '
          'carry on. The date and version you accepted are recorded '
          'against your account.',
    ),
    TermsClause(
      heading: 'If you do not accept',
      body:
          'You can sign out instead. The account stays as it is and '
          'nothing is recorded against it, but you will not be able to '
          'use the system until you accept. If that is a problem, it is a '
          'conversation to have with your school rather than with this '
          'screen.',
    ),
  ];

  /// What the privacy notice covers, so the two pages do not each try to
  /// be the other.
  static const String privacyPointer =
      'What is recorded about you, why, and who can see it is set out '
      'separately in the privacy notice, which you can open at any time '
      'from your profile.';
}

class TermsClause {
  final String heading;
  final String body;
  const TermsClause({required this.heading, required this.body});
}
