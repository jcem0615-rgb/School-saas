import '../core/constants/user_roles.dart';

/// What to look at, per role.
///
/// The demo has twelve accounts and ten portals, and somebody being shown
/// it for the first time lands on a dashboard of tiles with no idea which
/// one is the point. Every previous module seeded data with a story in it
/// -- a family who has gone quiet, a student behind on an instalment, a
/// shelf that has run out -- and none of that is discoverable by looking
/// at a grid of icons.
///
/// So each role gets one line naming the single thing worth opening. Not
/// a feature list: the tile is already on the screen. This is the reason
/// to tap it, phrased as what somebody would actually find there.
///
/// Kept beside the seed data rather than in the switcher widget, because
/// these two have to agree. A line promising two families to ring back is
/// wrong the moment the seed changes, and having them in one directory is
/// the closest thing to making that hard to miss.
const demoTourNotes = <UserRole, String>{
  UserRole.owner:
      'Platform side, above the schools. Add a school, or open System '
      'Check -- the preflight that says whether a real deployment actually '
      'works.',
  UserRole.director:
      'Payroll and Expenses sit together: salaries are the larger of the '
      'two. Reports has the enrolment and collection figures a board asks '
      'for.',
  UserRole.admin:
      'Grading Scheme is where the weights behind every report card are '
      'confirmed. Payroll is set up but the tables are the school\'s to '
      'type.',
  UserRole.principal:
      'The head count and no money -- deliberately. A principal sees who '
      'is enrolled, not what they owe.',
  UserRole.registrar:
      'Admissions opens on the families nobody has rung in a week. Then '
      'Records & Forms, which prints a report card and logs that it left '
      'the office.',
  UserRole.faculty:
      'Grade Submission: pick Mathematics and Grade 10 - Rizal. The marks '
      'are already weighted the DepEd way, and one student is below 75.',
  UserRole.staff:
      'Inventory. The bond paper is under its reorder level and a '
      'projector is out with a teacher.',
  UserRole.guidance:
      'Records and Summons -- and a summons tells the student and the '
      'parent, which is the half schools do by rumour.',
  UserRole.student:
      'Open a subject. The grade is computed from written work and '
      'performance tasks, and it says which component is still missing.',
  UserRole.parent:
      'The balance, what it is made of, and the instalments behind it. '
      'Pay Online takes a screenshot the registrar then reviews.',
};

/// The one line the demo leads with, before any role is chosen.
const demoTourIntro =
    'A whole school with twelve accounts, running on in-memory data -- no '
    'Firebase, nothing to set up. Every portal below is the real app; only '
    'the repositories underneath are swapped.';
