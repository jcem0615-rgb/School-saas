import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../domain/entities/conversation.dart';
import '../controllers/messaging_controller.dart';

final _stampFormat = DateFormat('d MMM, h:mm a');

/// One thread.
class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Opening the thread is reading it. Only this account's own count is
    // cleared -- the rules refuse anything else, which is what stops
    // "I read it" from becoming "you read it".
    Future.microtask(() => ref
        .read(messagingActionControllerProvider.notifier)
        .markRead(widget.conversationId));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    // Cleared first: a send that leaves the text in the box invites the
    // second tap that sends it twice.
    _controller.clear();

    final controller = ref.read(messagingActionControllerProvider.notifier);
    final ok = await controller.send(
      conversationId: widget.conversationId,
      text: text,
    );
    if (!mounted) return;
    if (!ok) {
      // Put it back rather than losing what they typed.
      _controller.text = text;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(controller.errorMessage ?? 'That message was not sent.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myUid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';
    final async = ref.watch(conversationMessagesProvider(widget.conversationId));
    final conversation = ref
        .watch(myConversationsProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation?.otherName(myUid) ?? 'Messages'),
        bottom: conversation == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'About ${conversation.studentName}'
                    '${conversation.section.isEmpty ? '' : ' · ${conversation.section}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('This thread could not be loaded: $err',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (messages) => messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nothing said yet. Say hello.'),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      // Anchored at the newest, which is where a thread
                      // is read from. Starting at the top would open a
                      // year-old conversation at its first line.
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final message = messages[messages.length - 1 - i];
                        return _Bubble(
                          message: message,
                          mine: message.senderUid == myUid,
                        );
                      },
                    ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  message.senderName,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              Text(message.text, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                // "Sending" rather than a blank, for the one frame
                // between writing a message and the server stamping it.
                message.sentAt == null
                    ? 'Sending…'
                    : _stampFormat.format(message.sentAt!),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
