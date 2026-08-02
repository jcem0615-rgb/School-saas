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
  const AnnouncementAudience({required this.all, required this.roles});

  static const everyone = AnnouncementAudience(all: true, roles: []);

  /// Everyone who works at the school -- the sensible default for
  /// operational notices (payroll, timesheets) that students and parents
  /// have no use for.
  static final staffOnly = AnnouncementAudience(
    all: false,
    roles: UserRole.values.where((r) => r.isStaffRole).map((r) => r.value).toList(),
  );

  bool includes(UserRole role) => all || roles.contains(role.value);

  /// How the targeting reads on a staff screen: "Everyone", or the roles
  /// named. Kept on the entity so a list row and the editor cannot
  /// describe the same audience differently.
  String get label {
    if (all) return 'Everyone';
    if (roles.isEmpty) return 'No one';
    final named = roles.map((r) => UserRole.fromString(r).displayName).toList()..sort();
    return named.join(', ');
  }
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final bool pinned;
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
  });
}
