/// Who an announcement targets. 'all' shows to every role in the school;
/// otherwise it's shown only to users whose role is in [roles].
class AnnouncementAudience {
  final bool all;
  final List<String> roles;
  const AnnouncementAudience({required this.all, required this.roles});

  static const everyone = AnnouncementAudience(all: true, roles: []);
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
