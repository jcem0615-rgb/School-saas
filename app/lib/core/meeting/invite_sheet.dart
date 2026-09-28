import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'class_passcode.dart';
import 'invite_link.dart';

/// How a teacher invites a class to a lesson already running.
///
/// Two things, kept apart on purpose.
///
/// The **link** is an address. It is meant to be forwarded -- into a
/// class group chat, to a parent, to the pupil who was off sick -- and
/// it is built so that forwarding it gives nothing away: no room name,
/// no code, only which school and which lesson. Everything that decides
/// who comes in is decided on the server after the person signs in.
///
/// The **code** is the second lock, and it is not in the link and not
/// in the message the link comes in. It is read out loud, at the start
/// of the lesson, to the people who are there. Copied together they
/// become one thing to forward and the code stops being a lock at all,
/// which is why there are two buttons here and not one.
class InviteSheet extends StatelessWidget {
  final String subject;
  final String section;

  /// Where the lesson is, or null when the app cannot build a web
  /// address for it -- on a phone build there is no page to link to.
  final Uri? link;

  /// What the teacher reads out. Null on a lesson that has none.
  final String? passcode;

  const InviteSheet({
    super.key,
    required this.subject,
    required this.section,
    required this.link,
    required this.passcode,
  });

  Future<void> _copy(BuildContext context, String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = link;
    final code = passcode;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invite to this class', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$subject · $section',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            Text('Link', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            if (address == null)
              Text(
                'A link can only be sent from the web version of '
                'LogicClass. Read the class code out instead.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  address.toString(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _copy(context, 'Link', address.toString()),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(
                      context,
                      'Message',
                      inviteMessage(
                        subject: subject,
                        section: section,
                        link: address,
                      ),
                    ),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('Copy message'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Safe to forward. It says which class, not how to get in.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            const Divider(height: 32),

            Text('Class code', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            if (code == null || code.isEmpty)
              Text(
                'This class has no code.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              SelectableText(
                displayClassPasscode(code),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _copy(context, 'Code', displayClassPasscode(code)),
                icon: const Icon(Icons.key, size: 18),
                label: const Text('Copy code'),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.campaign_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // Two buttons and not one, and this is why.
                      'Read this out at the start of the lesson. Sending it '
                      'in the same message as the link makes them one thing '
                      'to forward, and the code stops being a second lock.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
