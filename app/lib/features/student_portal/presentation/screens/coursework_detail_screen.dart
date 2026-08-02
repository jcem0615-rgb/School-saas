import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../faculty_portal/domain/entities/coursework_item.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// Full detail for one assignment, exam, lesson or project.
///
/// The feed row only has room for a title and a due date, which is not
/// enough to actually do the work -- the description and any attached file
/// are the point. This is the screen a student lands on from either the
/// coursework feed or a subject.
class CourseworkDetailScreen extends ConsumerWidget {
  final CourseworkItem item;
  const CourseworkDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overdue = item.dueDate != null &&
        item.dueDate!.isBefore(DateTime.now()) &&
        item.type.isGradable;
    final online = item.delivery == CourseworkDelivery.online;

    return Scaffold(
      appBar: AppBar(title: Text(item.type.displayLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(item.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.menu_book_outlined, size: 16),
                label: Text(item.subject),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                avatar: const Icon(Icons.groups_outlined, size: 16),
                label: Text(item.section),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                avatar: Icon(
                  item.delivery == CourseworkDelivery.online
                      ? Icons.cloud_outlined
                      : Icons.meeting_room_outlined,
                  size: 16,
                ),
                label: Text(item.delivery.displayLabel),
                visualDensity: VisualDensity.compact,
              ),
              if (item.totalPoints != null)
                Chip(
                  avatar: const Icon(Icons.star_outline, size: 16),
                  label: Text('${item.totalPoints!.toStringAsFixed(0)} points'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (item.dueDate != null)
            Card(
              // Overdue is called out rather than left for the student to
              // work out from a date: a missed deadline is the single most
              // consequential thing on this screen.
              color: overdue ? theme.colorScheme.errorContainer : null,
              child: ListTile(
                leading: Icon(
                  overdue ? Icons.warning_amber_outlined : Icons.event_outlined,
                  color: overdue ? theme.colorScheme.onErrorContainer : null,
                ),
                title: Text(
                  overdue ? 'Overdue' : 'Due',
                  style: TextStyle(
                    color: overdue ? theme.colorScheme.onErrorContainer : null,
                  ),
                ),
                subtitle: Text(
                  _dateFormat.format(item.dueDate!),
                  style: TextStyle(
                    color: overdue ? theme.colorScheme.onErrorContainer : null,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            item.description.trim().isEmpty
                ? 'No further details were provided.'
                : item.description,
          ),
          if (online && item.attachmentUrl == null) ...[
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('The material is missing'),
                subtitle: const Text(
                  'This is marked online but has no file attached. Ask your '
                  'teacher to add it.',
                ),
              ),
            ),
          ],
          if (item.attachmentUrl != null) ...[
            const SizedBox(height: 20),
            Text(
              online ? 'Take it here' : 'Attachment',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Card(
              // For online work this file IS the work -- the teacher had
              // to attach one before they could publish it -- so it gets
              // the emphasis rather than sitting at the bottom like a
              // supporting handout.
              color: online ? theme.colorScheme.primaryContainer : null,
              child: ListTile(
                leading: Icon(
                  online ? Icons.play_circle_outline : Icons.insert_drive_file_outlined,
                  color: online ? theme.colorScheme.onPrimaryContainer : null,
                ),
                title: Text(item.attachmentName ?? 'Attached file'),
                subtitle: Text(online ? 'Open to take this online' : 'Tap to open'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.parse(item.attachmentUrl!);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Could not open the attachment.')),
                      );
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Posted by ${item.teacherName} · ${_dateFormat.format(item.createdAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
