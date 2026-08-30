import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/app_notification.dart';
import '../models/app_notification_model.dart';

/// Reads and marks off one person's inbox.
///
/// The uid is in the path, not in a `where` clause, and that is the
/// security model rather than a detail of layout: there is no query
/// anybody can write from this app that returns somebody else's
/// notifications. A flat `notifications` collection filtered by a
/// `userId` field would need a rule to defend every read, and one screen
/// that forgot the filter would hand a parent every other family's
/// alerts.
class NotificationsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  /// Enough to scroll through, and a hard ceiling on what one screen can
  /// cost. Nothing older than the last hundred notifications is
  /// something anybody scrolls to find; it is something the source
  /// record is looked up for.
  static const pageSize = 100;

  const NotificationsRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection(FirestorePaths.notificationItems(_schoolId, _uid));

  Stream<List<AppNotification>> watch() {
    return _items
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AppNotificationModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<void> markRead(String notificationId) async {
    await _items.doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  /// One batch, over what is unread right now.
  ///
  /// Read from the server rather than from whatever the stream last
  /// emitted, because the two can differ by anything that arrived in
  /// between -- and "mark all read" that leaves one unread is a bell
  /// that will not go out.
  Future<void> markAllRead() async {
    final unread = await _items
        .where('isRead', isEqualTo: false)
        .limit(pageSize)
        .get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
