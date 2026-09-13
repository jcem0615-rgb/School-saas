import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/notifications/data/datasources/notifications_remote_datasource.dart';

/// "Mark all read" over an inbox bigger than one page.
///
/// The defect: the datasource ran one `.limit(100).get()` under a comment
/// saying that leaving a single item unread is "a bell that will not go
/// out". Firestore returns an unordered query in document-id order, and
/// these ids are `{kind}_{sourceId}` -- so the hundred it marked were the
/// alphabetically first hundred, every `announcement_*` before any
/// `emergency_*`. A parent back from a fortnight away pressed the button
/// and the badge stayed lit.
///
/// Driven through the loop the datasource actually calls, with a fake
/// inbox in place of Firestore, because the bug was in the paging and
/// nowhere else.
void main() {
  /// An inbox of [total] unread items that answers a limited query the
  /// way Firestore does -- a page at a time, removing what was marked.
  ({
    Future<List<int>> Function(int) fetch,
    Future<void> Function(List<int>) commit,
    List<int> Function() remaining,
    int Function() passes,
  }) inboxOf(int total) {
    final unread = List<int>.generate(total, (i) => i);
    var passes = 0;
    return (
      fetch: (limit) async {
        passes++;
        return unread.take(limit).toList();
      },
      commit: (page) async => unread.removeWhere(page.contains),
      remaining: () => unread,
      passes: () => passes,
    );
  }

  Future<int> markAll(
    ({
      Future<List<int>> Function(int) fetch,
      Future<void> Function(List<int>) commit,
      List<int> Function() remaining,
      int Function() passes,
    }) inbox, {
    int pageLimit = 500,
    int maxPasses = 500,
  }) =>
      NotificationsRemoteDataSource.markEveryUnread<int>(
        fetch: inbox.fetch,
        commit: inbox.commit,
        pageLimit: pageLimit,
        maxPasses: maxPasses,
      );

  test('an inbox smaller than a page is cleared in one pass', () async {
    final inbox = inboxOf(12);
    expect(await markAll(inbox), 12);
    expect(inbox.remaining(), isEmpty);
    // One fetch, not two: a short page is the end of the list, and going
    // back for an empty one is a round trip per press of the button.
    expect(inbox.passes(), 1);
  });

  test('an empty inbox writes nothing at all', () async {
    final inbox = inboxOf(0);
    expect(await markAll(inbox), 0);
    expect(inbox.passes(), 1);
  });

  test('an inbox exactly one page long takes a second look', () async {
    // The one case a short-page check alone gets wrong: 500 of 500 looks
    // identical to "there is more", so it has to ask again to find out.
    final inbox = inboxOf(500);
    expect(await markAll(inbox), 500);
    expect(inbox.remaining(), isEmpty);
    expect(inbox.passes(), 2);
  });

  test('an inbox several pages long is cleared, not topped up', () async {
    // The parent back from a fortnight away. Under the old code this
    // left 640 unread and the bell lit.
    final inbox = inboxOf(1140);
    expect(await markAll(inbox), 1140);
    expect(inbox.remaining(), isEmpty, reason: 'the bell has to go out');
    expect(inbox.passes(), 3);
  });

  test('and it stops rather than looping forever', () async {
    // A fetch that keeps handing back the same page -- a write that
    // silently fails, a rule that refuses the update. The loop has to
    // end; a client that spins here burns a phone's battery and its
    // owner's data allowance on a button they pressed once.
    var fetches = 0;
    final marked = await NotificationsRemoteDataSource.markEveryUnread<int>(
      fetch: (limit) async {
        fetches++;
        return List<int>.generate(limit, (i) => i);
      },
      commit: (_) async {},
      pageLimit: 10,
      maxPasses: 4,
    );
    expect(fetches, 4);
    expect(marked, 40);
  });

  test('the page size is the batch ceiling, not the screen page', () async {
    // 500 is what a Firestore batch takes. Paging at the screen's 100
    // would be five times the round trips for the same work.
    expect(NotificationsRemoteDataSource.batchLimit, 500);
    expect(NotificationsRemoteDataSource.pageSize, 100);
  });
}
