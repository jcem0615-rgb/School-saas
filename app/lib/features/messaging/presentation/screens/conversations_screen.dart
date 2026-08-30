import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../domain/entities/conversation.dart';
import '../../../../core/constants/user_roles.dart';
import '../controllers/messaging_controller.dart';
import '../widgets/new_conversation_sheet.dart';
import 'chat_screen.dart';

final _dayFormat = DateFormat('d MMM');
final _clock = DateFormat('h:mm a');

/// Every thread this person is in.
///
/// A parent sees one row per teacher per child; a teacher sees one per
/// family. Nobody else sees any of it -- not the office, not another
/// teacher. That is enforced by the rules and it is the reason the
/// feature is usable: a parent who thinks the principal is reading tells
/// the teacher nothing worth reading.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myConversationsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final uid = user?.uid ?? '';
    // Only the two roles that can be in one of these. Everybody else
    // reaches this screen through the notification inbox at most, and a
    // button that always refuses is worse than no button.
    final canStart =
        user?.role == UserRole.parent || user?.role == UserRole.faculty;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: !canStart
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final id = await showNewConversationSheet(context);
                if (id == null || !context.mounted) return;
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatScreen(conversationId: id),
                ));
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Your messages could not be loaded: $err',
                textAlign: TextAlign.center),
          ),
        ),
        data: (conversations) => conversations.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No conversations yet. A parent can start one from their '
                    "child's page; a teacher from their class roll.",
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _ConversationTile(
                  conversation: conversations[i],
                  myUid: uid,
                ),
              ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String myUid;

  const _ConversationTile({required this.conversation, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = conversation.unreadFor(myUid);
    final other = conversation.otherName(myUid);

    return ListTile(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversation.id),
      )),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          other.isEmpty ? '?' : other.characters.first.toUpperCase(),
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        other,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Which child, always. A teacher with thirty families and a
          // parent with four teachers both need it, and a thread that
          // does not say is one somebody has to open to identify.
          Text(
            'About ${conversation.studentName}'
            '${conversation.section.isEmpty ? '' : ' · ${conversation.section}'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            conversation.isEmpty
                ? 'No messages yet'
                : conversation.lastMessage ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(
              _stamp(conversation.lastMessageAt!),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (unread > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Today's messages read as a time; older ones as a date. A column of
  /// "9:14 AM" with no dates is a thread whose age nobody can tell.
  static String _stamp(DateTime at) {
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? _clock.format(at) : _dayFormat.format(at);
  }
}
