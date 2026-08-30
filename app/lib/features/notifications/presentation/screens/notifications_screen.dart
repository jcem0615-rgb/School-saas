import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/push/push_providers.dart';
import '../../domain/entities/app_notification.dart';
import '../controllers/notifications_controller.dart';

final _dateTimeFormat = DateFormat('d MMM y, h:mm a');

/// Whether this device is set up to receive push notifications.
///
/// Asked of the registrar rather than remembered as a preference,
/// because a person can revoke notification permission in their browser
/// or phone settings without ever opening the app, and a card that
/// offered to turn on something already on would be a card nobody
/// trusted.
final _pushRegisteredProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(pushRegistrarProvider).isRegistered(),
);

/// Everything the school has told this person.
///
/// The dependable half of notifications. The push is the fast channel
/// and it fails quietly and often -- a phone that was off, permission
/// never granted, a token that expired. This list does not: it is the
/// same set of messages, still here tomorrow, and it is where somebody
/// goes to find out what they missed.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final busy = ref.watch(notificationsActionControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: (unread == 0 || busy)
                ? null
                : () => ref
                    .read(notificationsActionControllerProvider.notifier)
                    .markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Your notifications could not be loaded: $err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) => ListView(
          children: [
            const _PushPermissionCard(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Text(
                  'Nothing yet. Announcements, guidance appointments and '
                  'alerts for you will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final item in items)
              _NotificationTile(
                item: item,
                onTap: () => _open(context, ref, item),
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, AppNotification item) {
    if (!item.isRead) {
      ref.read(notificationsActionControllerProvider.notifier).markRead(item.id);
    }
    // A link back to this screen is the common case -- the notification
    // already says everything -- and pushing it would stack a second
    // copy of the inbox on top of the first.
    if (item.link.isNotEmpty && item.link != '/notifications') {
      context.push(item.link);
    }
  }
}

/// The one place the app asks for notification permission.
///
/// Not on launch. A permission prompt in front of somebody who opened
/// the app to check a grade is a prompt that gets dismissed, and a
/// dismissed browser prompt cannot be asked again -- the next one has to
/// come from the person themselves, in site settings, which almost
/// nobody finds. So it is asked here, where notifications are what the
/// person is already looking at, and where "yes" is obviously the answer
/// to a question they came to this screen with.
class _PushPermissionCard extends ConsumerStatefulWidget {
  const _PushPermissionCard();

  @override
  ConsumerState<_PushPermissionCard> createState() => _PushPermissionCardState();
}

class _PushPermissionCardState extends ConsumerState<_PushPermissionCard> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final on = await ref.read(pushRegistrarProvider).register();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(_pushRegisteredProvider);
    if (!on) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
            'Notifications are blocked for this app. Allow them in your '
            'browser or phone settings, then try again.',
          ),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final registered = ref.watch(_pushRegisteredProvider).valueOrNull;
    // Nothing at all while the answer is unknown, and nothing once it is
    // on. A card that flickered into view and out again on every visit
    // would read as an error.
    if (registered != false) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      elevation: 0,
      color: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Get these on your phone',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Turn on notifications and this device will be told about '
              'announcements, guidance appointments and emergencies as they '
              'happen. Everything still appears on this screen either way.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _enable,
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Turn on notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour) = _appearance(theme, item.kind);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: colour.withValues(alpha: 0.15),
        child: Icon(icon, color: colour, size: 20),
      ),
      title: Text(
        item.title,
        style: theme.textTheme.titleSmall?.copyWith(
          // Unread is carried by weight and a dot, not by colour alone --
          // the same reason every other status in this app is not just a
          // coloured pixel.
          fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.body),
          const SizedBox(height: 2),
          Text(
            item.createdAt == null ? 'Just now' : _dateTimeFormat.format(item.createdAt!),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: item.isRead
          ? null
          : Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
    );
  }

  static (IconData, Color) _appearance(ThemeData theme, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.emergency => (Icons.emergency_outlined, theme.colorScheme.error),
        NotificationKind.summons => (Icons.event_available_outlined, theme.colorScheme.tertiary),
        NotificationKind.announcement => (Icons.campaign_outlined, theme.colorScheme.primary),
        NotificationKind.payment => (Icons.payments_outlined, theme.colorScheme.primary),
        NotificationKind.approval => (Icons.rule_outlined, theme.colorScheme.primary),
        NotificationKind.general => (Icons.notifications_outlined, theme.colorScheme.primary),
      };
}
