import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_remote_datasource.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  final NotificationsRemoteDataSource _remote;
  const NotificationsRepositoryImpl(this._remote);

  @override
  Stream<List<AppNotification>> watch() => _remote.watch();

  @override
  Future<Result<void>> markRead(String notificationId) =>
      _run(() => _remote.markRead(notificationId));

  @override
  Future<Result<void>> markAllRead() => _run(_remote.markAllRead);

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}

/// What the app uses when nobody is signed in.
///
/// Returns an empty inbox instead of throwing. The bell lives in app
/// bars that stay on screen for the frame or two between signing out and
/// the router reaching the login screen, and a provider that threw there
/// would replace the whole dashboard with a red error box on the way
/// out.
class SignedOutNotificationsRepository implements NotificationsRepository {
  const SignedOutNotificationsRepository();

  @override
  Stream<List<AppNotification>> watch() => const Stream.empty();

  @override
  Future<Result<void>> markRead(String notificationId) async => const Success(null);

  @override
  Future<Result<void>> markAllRead() async => const Success(null);
}
