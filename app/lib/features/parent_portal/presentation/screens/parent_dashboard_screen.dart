import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../messaging/presentation/controllers/messaging_controller.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';
import '../../../director_portal/presentation/screens/announcements_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../emergency/presentation/controllers/emergency_controller.dart';
import '../../../emergency/presentation/screens/parent_alerts_screen.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../controllers/parent_controller.dart';
import 'child_detail_screen.dart';

class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(myChildrenProvider);
    final activeAlerts = ref.watch(childrenActiveAlertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Children'),
        actions: [
          const NotificationBell(),
          // Profile was routed but nothing navigated to it, so the one
          // screen every role shares -- and the only way into the
          // privacy notice and data requests -- could not be opened at
          // all. A route with no door is a screen that does not exist.
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My Activity',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
          ),
          // Badged, because the point of a message from a teacher is
          // that it is waiting, and an unbadged icon is one nobody taps
          // on the day it matters.
          Consumer(
            builder: (context, ref, _) {
              final unread = ref.watch(unreadMessageCountProvider);
              return IconButton(
                icon: Badge(
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.forum_outlined),
                ),
                tooltip: unread == 0 ? 'Messages' : 'Messages, $unread unread',
                onPressed: () => context.push('/messages'),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Announcements',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.emergency_share_outlined),
            tooltip: 'Emergency Alerts',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ParentAlertsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // An unresolved alert is not something to put behind an icon.
          // The push may never have arrived -- permission declined, phone
          // in a bag, notifications never configured -- so a parent who
          // opens the app for any other reason has to be told without
          // having to go looking.
          if (activeAlerts.isNotEmpty)
            _ActiveAlertBanner(count: activeAlerts.length, name: activeAlerts.first.studentName),
          Expanded(child: _children(context, ref, childrenAsync)),
        ],
      ),
    );
  }

  Widget _children(BuildContext context, WidgetRef ref, AsyncValue<List<StudentSummary>> childrenAsync) {
    return childrenAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load children: $err')),
        data: (children) {
          if (children.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No children are linked to this account yet. Please contact your school registrar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final child = children[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: child.photoUrl != null ? NetworkImage(child.photoUrl!) : null,
                    child: child.photoUrl == null ? const Icon(Icons.school_outlined) : null,
                  ),
                  title: Text(child.fullName),
                  subtitle: Text('${child.studentNumber} · ${child.classLabel}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ChildDetailScreen(child: child))),
                ),
              );
            },
          );
        },
    );
  }
}

/// The one thing on this screen that cannot wait for a tap.
class _ActiveAlertBanner extends StatelessWidget {
  final int count;
  final String name;

  const _ActiveAlertBanner({required this.count, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.error,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ParentAlertsScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.emergency_share, color: theme.colorScheme.onError),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '$name pressed the emergency button'
                          : '$count emergency alerts',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.onError),
                    ),
                    Text(
                      'Tap for where they are and who is responding',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onError),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onError),
            ],
          ),
        ),
      ),
    );
  }
}
