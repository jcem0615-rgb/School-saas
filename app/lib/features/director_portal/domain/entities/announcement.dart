import '../../../../core/constants/user_roles.dart';

/// Who an announcement targets. [all] shows it to every role in the
/// school; otherwise only to users whose role is in [roles].
///
/// **This is targeting, not access control.** Announcements are readable
/// tenant-wide in firestore.rules and that is deliberate: Firestore rules
/// reject queries, they do not filter them, so a per-document audience
/// rule would fail the whole list query for anyone whose role did not
/// match every document it returned. Never put anything in an
/// announcement that a student must not read -- hiding a payroll date
/// from them by relevance is right, and it is exactly the kind of thing
/// that must not be protected by secrecy.
class AnnouncementAudience {
  final bool all;
  final List<String> roles;

  /// Section names this is addressed to, e.g. "Grade 10 - Rizal".
  ///
  /// This is what a teacher posts to. A role is the wrong unit for them:
  /// "Students" means every student in the school, and a Grade 10 adviser
  /// reminding their class to bring a permit slip should not put it in
  /// front of the Grade 3s. A section is also the unit a student, their
  /// parent and their teachers already have in common, so it needs no new
  /// grouping to be maintained alongside the roster.
  final List<String> sections;

  const AnnouncementAudience({
    required this.all,
    required this.roles,
    this.sections = const [],
  });

  static const everyone = AnnouncementAudience(all: true, roles: []);

  /// Addressed to particular classes -- what a teacher's post uses.
  factory AnnouncementAudience.forSections(Iterable<String> sections) =>
      AnnouncementAudience(all: false, roles: const [], sections: sections.toList());

  /// Everyone who works at the school -- the sensible default for
  /// operational notices (payroll, timesheets) that students and parents
  /// have no use for.
  static final staffOnly = AnnouncementAudience(
    all: false,
    roles: UserRole.values.where((r) => r.isStaffRole).map((r) => r.value).toList(),
  );

  /// Whether this is addressed to a viewer with [role] who belongs to
  /// [viewerSections].
  ///
  /// Role and section are an OR, not an AND. A notice for "Grade 10 -
  /// Rizal" has to reach that section's students, their parents and the
  /// other teachers who take them, and enumerating those roles alongside
  /// the section would mean a teacher choosing both -- and getting it
  /// wrong in the direction that leaves the parents out.
  bool includes(UserRole role, {Iterable<String> viewerSections = const []}) {
    if (all || roles.contains(role.value)) return true;
    if (sections.isEmpty) return false;
    return viewerSections.any(sections.contains);
  }

  /// How the targeting reads on a staff screen: "Everyone", or the roles
  /// named. Kept on the entity so a list row and the editor cannot
  /// describe the same audience differently.
  String get label {
    if (all) return 'Everyone';
    final named = roles.map((r) => UserRole.fromString(r).displayName).toList()..sort();
    final parts = [...named, ...sections];
    if (parts.isEmpty) return 'No one';
    return parts.join(', ');
  }

  /// True when nothing was chosen -- the state the editor must not let
  /// somebody post from.
  bool get reachesNobody => !all && roles.isEmpty && sections.isEmpty;
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final bool pinned;

  /// Who posted it. [createdBy] is the uid, which is what decides whether
  /// the signed-in teacher may edit this one -- firestore.rules pins
  /// authorship on update, and a screen that offered an Edit button the
  /// rules would refuse is worse than no button.
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.pinned,
    required this.createdByName,
    required this.createdAt,
    this.createdBy = '',
  });
}
