import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/app_notification.dart';

class AppNotificationModel {
  const AppNotificationModel._();

  static AppNotification fromFirestore(String id, Map<String, dynamic> data) {
    return AppNotification(
      id: id,
      kind: NotificationKind.fromString(data['kind'] as String?),
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      // Falls back to the inbox itself rather than to nothing: a
      // notification whose link the server forgot should still open
      // somewhere sensible when tapped.
      link: (data['link'] as String?) ?? '/notifications',
      sourceId: (data['sourceId'] as String?) ?? '',
      // Null for exactly one snapshot, while the server timestamp is
      // still being written.
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isRead: (data['isRead'] as bool?) ?? false,
    );
  }
}
