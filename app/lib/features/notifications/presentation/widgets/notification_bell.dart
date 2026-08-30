import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/notifications_controller.dart';

/// The bell every portal carries in its app bar.
///
/// One widget rather than ten copies, because the count has to mean the
/// same thing on a parent's dashboard and a director's, and because the
/// next portal added should get it by writing one line.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      tooltip: unread == 0
          ? 'Notifications'
          : 'Notifications, $unread unread',
      icon: Badge(
        // Counts above ninety-nine stop being a number anybody reads and
        // start being a shape that breaks the layout.
        label: unread > 99 ? const Text('99+') : Text('$unread'),
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}
