/// What kind of thing happened.
///
/// Drives the icon and the colour in the list, and nothing else -- the
/// text is written by whatever sent it. Unknown values fall back to
/// [general] rather than throwing, because a server that learns to send
/// a new kind must not break every app installed before it did.
enum NotificationKind {
  announcement('announcement'),
  emergency('emergency'),
  summons('summons'),
  payment('payment'),
  approval('approval'),
  general('general');

  final String value;
  const NotificationKind(this.value);

  static NotificationKind fromString(String? value) =>
      NotificationKind.values.firstWhere(
        (k) => k.value == value,
        orElse: () => NotificationKind.general,
      );
}

/// One thing the school told one person.
///
/// The durable half of a notification. A push notification is gone the
/// moment it is swiped away, and never arrives at all for a phone that
/// was off, a browser that never granted permission, or a token that
/// went stale three weeks ago. This is the copy that is still there
/// tomorrow.
///
/// Written only by Cloud Functions (see
/// `functions/src/shared/notify/deliver.ts`); firestore.rules lets the
/// recipient change exactly one thing about it, which is whether they
/// have read it.
class AppNotification {
  final String id;
  final NotificationKind kind;
  final String title;

  /// The whole message, not the truncated lock-screen preview.
  final String body;

  /// Where tapping it should go, as an in-app route.
  final String link;

  /// The thing it is about -- a summons id, an announcement id. Kept so
  /// a screen can open the source record rather than only describe it.
  final String sourceId;

  /// Null while the server timestamp is still in flight, which lasts one
  /// snapshot. Callers sort nulls first: a notification that has only
  /// just arrived is the newest one there is.
  final DateTime? createdAt;

  final bool isRead;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.sourceId,
    required this.createdAt,
    required this.isRead,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        link: link,
        sourceId: sourceId,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );
}
