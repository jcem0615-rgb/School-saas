import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Firestore's per-batch write ceiling, and so the size of one pass of
  /// [markAllRead].
  static const batchLimit = 500;

  /// A stop on [markAllRead]'s loop. See the note there.
  static const maxPasses = 500;

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

  /// Everything unread, not one page of it.
  ///
  /// Read from the server rather than from whatever the stream last
  /// emitted, because the two can differ by anything that arrived in
  /// between -- and "mark all read" that leaves one unread is a bell
  /// that will not go out.
  ///
  /// That sentence was written above a single `.limit(100).get()`, which
  /// is exactly the bell it warns about. Firestore returns an unordered
  /// query in document-id order, and these ids are `{kind}_{sourceId}`,
  /// so the hundred it marked were the alphabetically first hundred --
  /// every `announcement_*` before any `emergency_*`. A parent back from
  /// a fortnight away with a hundred and forty unread pressed the button,
  /// watched the badge stay lit, and what stayed unread could be the
  /// alert about their own child. Pressing it again marked another
  /// arbitrary hundred.
  Future<void> markAllRead() async {
    await markEveryUnread<DocumentReference<Map<String, dynamic>>>(
      fetch: (limit) async {
        final snap =
            await _items.where('isRead', isEqualTo: false).limit(limit).get();
        return snap.docs.map((d) => d.reference).toList();
      },
      commit: (page) async {
        final batch = _firestore.batch();
        for (final ref in page) {
          batch.update(ref, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      },
    );
  }

  /// The paging loop behind [markAllRead], with Firestore held at arm's
  /// length so it can be driven in a test.
  ///
  /// [pageLimit] is Firestore's per-batch write ceiling. [maxPasses] is a
  /// stop, not a budget -- an inbox still reporting unread after a
  /// quarter of a million of them is a bug somewhere else, and a client
  /// loop is the wrong place to find out.
  ///
  /// Nothing else marks these read, so no pass can be undone by another
  /// writer: a page that comes back short is the last one, and a full
  /// page means look again. Returns how many were marked.
  @visibleForTesting
  static Future<int> markEveryUnread<T>({
    required Future<List<T>> Function(int limit) fetch,
    required Future<void> Function(List<T> page) commit,
    int pageLimit = batchLimit,
    int maxPasses = NotificationsRemoteDataSource.maxPasses,
  }) async {
    var marked = 0;
    for (var pass = 0; pass < maxPasses; pass++) {
      final page = await fetch(pageLimit);
      if (page.isEmpty) return marked;
      await commit(page);
      marked += page.length;
      if (page.length < pageLimit) return marked;
    }
    return marked;
  }
}
