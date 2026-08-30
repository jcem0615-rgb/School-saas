import '../../../../core/errors/result.dart';
import '../entities/app_notification.dart';

abstract class NotificationsRepository {
  /// The signed-in person's own inbox, newest first.
  ///
  /// A stream rather than a one-shot read, unlike the school totals
  /// card: the whole point of a notification is that it turns up while
  /// you are looking at something else, and a bell that only counted
  /// what was there when the app opened would be a bell that never rang.
  Stream<List<AppNotification>> watch();

  Future<Result<void>> markRead(String notificationId);

  /// Marks everything currently unread as read.
  ///
  /// Bounded, deliberately: an inbox nobody has opened in a year is not
  /// something to clear in one unbatched sweep.
  Future<Result<void>> markAllRead();
}
