import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/notifications_remote_datasource.dart';
import '../../data/repositories_impl/notifications_repository_impl.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    return const SignedOutNotificationsRepository();
  }
  return NotificationsRepositoryImpl(
    NotificationsRemoteDataSource(
      firestore: ref.watch(firestoreProvider),
      schoolId: user.schoolId!,
      uid: user.uid,
    ),
  );
});

/// The inbox, newest first.
///
/// Sorted here as well as in the query, because a notification that has
/// only just arrived carries a null `createdAt` for one snapshot while
/// the server timestamp is written -- and Firestore's own ordering puts
/// those last, which is exactly backwards for the one item the person is
/// most likely waiting for.
final notificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).watch().map((items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return sorted;
  });
});

/// What the bell shows.
///
/// Zero while the first snapshot is in flight and zero on an error: a
/// badge is a claim that there is something to look at, and guessing
/// wrong in that direction sends somebody to an empty list.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return items.where((n) => !n.isRead).length;
});

/// Marking things read.
///
/// A StateNotifier only so the screen can disable "Mark all read" while
/// one is in flight. Failures are deliberately quiet: not being able to
/// mark a notification read is not worth a snackbar over the top of the
/// notification itself.
class NotificationsActionController extends StateNotifier<AsyncValue<void>> {
  final NotificationsRepository _repository;
  NotificationsActionController(this._repository) : super(const AsyncValue.data(null));

  Future<void> markRead(String id) async {
    await _repository.markRead(id);
  }

  Future<void> markAllRead() async {
    state = const AsyncValue.loading();
    await _repository.markAllRead();
    if (mounted) state = const AsyncValue.data(null);
  }
}

final notificationsActionControllerProvider =
    StateNotifierProvider<NotificationsActionController, AsyncValue<void>>((ref) {
  return NotificationsActionController(ref.watch(notificationsRepositoryProvider));
});
