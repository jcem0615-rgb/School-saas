import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/announcement.dart';
import '../controllers/director_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(announcementsStreamProvider);

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: announcementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load announcements: $err')),
        data: (announcements) {
          if (announcements.isEmpty) {
            return const Center(child: Text('No announcements yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final a = announcements[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (a.pinned) const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.push_pin, size: 16, color: Colors.orange),
                          ),
                          Expanded(
                            child: Text(a.title, style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(a.body),
                      const SizedBox(height: 8),
                      Text(
                        '${a.createdByName} · ${_dateFormat.format(a.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool pinned = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('New Announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: pinned,
                  onChanged: (v) => setState(() => pinned = v ?? false),
                  title: const Text('Pin to top'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final success = await ref.read(directorActionControllerProvider.notifier).createAnnouncement(
                      title: titleController.text,
                      body: bodyController.text,
                      audience: AnnouncementAudience.everyone,
                      pinned: pinned,
                    );
                if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}
