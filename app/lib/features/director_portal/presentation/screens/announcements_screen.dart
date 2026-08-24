import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../domain/entities/announcement.dart';
import '../controllers/director_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// Who may post to the whole school: the three roles firestore.rules
/// lets write any announcement. Faculty write too, but only to their own
/// classes and only their own posts, which is a different screen state
/// rather than a fourth entry here.
const _authoringRoles = [UserRole.director, UserRole.principal, UserRole.admin];

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  /// Null means "no audience filter". Only ever set by an author, since
  /// only they see the filter chips -- a student's list is already
  /// filtered to them and a second filter over it would mean nothing.
  UserRole? _audienceFilter;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role;
    final canAuthor = role != null && _authoringRoles.contains(role);
    final isFaculty = role == UserRole.faculty;
    // A teacher can only post to a class they are assigned to, so with no
    // assignments there is nothing to post to and no button to offer.
    final myClasses = ref.watch(myTeachingSectionsProvider);
    final canPostToClass = isFaculty && myClasses.isNotEmpty;

    // Three lists, because three people want different things here. A
    // director manages every notice. A teacher manages their own and
    // reads the ones addressed to them, which are not the same set. A
    // student just reads.
    final announcementsAsync =
        ref.watch(canAuthor ? allAnnouncementsStreamProvider : announcementsStreamProvider);
    final mineAsync = isFaculty ? ref.watch(myAnnouncementsStreamProvider) : null;

    ref.listen(directorActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: canAuthor || canPostToClass
          ? FloatingActionButton.extended(
              onPressed: () => _showEditor(context, classOptions: myClasses),
              icon: const Icon(Icons.add),
              label: Text(canPostToClass ? 'Post to a class' : 'New'),
            )
          : null,
      body: announcementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load announcements: $err')),
        data: (announcements) {
          // For a reader the stream is already their own list and the
          // filter is not shown. For an author it is everything posted,
          // and this is what previews one role's view of it.
          final visible = _audienceFilter == null
              ? announcements
              : announcements.where((a) => a.audience.includes(_audienceFilter!)).toList();

          // A teacher's own posts sort to the top and carry the edit
          // controls; everything else on their list is read-only. One
          // list rather than two sections: the audience line on each card
          // already says who a notice is for, and a second heading would
          // push the school's notices below the fold on a phone.
          final myUid = ref.watch(authStateProvider).valueOrNull?.uid;
          final mine = mineAsync?.valueOrNull ?? const <Announcement>[];
          final mineIds = mine.map((a) => a.id).toSet();
          final rows = isFaculty
              ? [...mine, ...visible.where((a) => !mineIds.contains(a.id))]
              : visible;

          return Column(
            children: [
              if (canAuthor) _AudienceFilterBar(
                selected: _audienceFilter,
                onChanged: (r) => setState(() => _audienceFilter = r),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            announcements.isEmpty
                                ? 'No announcements yet.'
                                : 'No announcements addressed to '
                                    '${_audienceFilter!.displayName}.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final a = rows[index];
                          // A teacher may edit only what they wrote --
                          // firestore.rules pins authorship on update, so
                          // an Edit button on anything else would just
                          // produce a permission error at the end of a
                          // filled-in form.
                          final editable =
                              canAuthor || (isFaculty && a.createdBy == myUid && myUid != null);
                          return _AnnouncementCard(
                            announcement: a,
                            canAuthor: editable,
                            onEdit: () =>
                                _showEditor(context, existing: a, classOptions: myClasses),
                            onDelete: () => _confirmDelete(context, a),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Announcement a) async {
    final ok = await confirmDelete(context, itemLabel: 'announcement', detail: a.title);
    if (!ok) return;
    await ref.read(directorActionControllerProvider.notifier).deleteAnnouncement(a.id);
  }

  /// One editor for both create and edit. The two differ only in which
  /// controller method runs on submit and in the labels, so keeping them
  /// as one builder means a new field can never be added to the create
  /// form and forgotten on the edit form.
  Future<void> _showEditor(
    BuildContext context, {
    Announcement? existing,
    List<TeacherAssignment> classOptions = const [],
  }) async {
    final isEdit = existing != null;
    // A teacher gets classes to choose from and no role chips; a
    // director gets role chips and no classes. Deciding it from the
    // options rather than the role keeps the editor one widget: there is
    // no second copy of it to forget a field on.
    final byClass = classOptions.isNotEmpty;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final bodyController = TextEditingController(text: existing?.body ?? '');
    bool pinned = existing?.pinned ?? false;
    // Everyone is the default because most notices are for everyone, and
    // because a wrongly-broad announcement is a nuisance while a wrongly-
    // narrow one means somebody never hears about the typhoon.
    // Everyone is the default for a school notice because most are for
    // everyone, and because a wrongly-broad announcement is a nuisance
    // while a wrongly-narrow one means somebody never hears about the
    // typhoon. A teacher's post is never school-wide: they are writing
    // to a class, and the default is the class they advise.
    bool toEveryone = byClass ? false : (existing?.audience.all ?? true);
    final selectedRoles = <String>{...?existing?.audience.roles};
    final selectedSections = <String>{
      ...?existing?.audience.sections,
      if (!isEdit && byClass) classOptions.first.section,
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(
            isEdit
                ? 'Edit Announcement'
                : byClass
                    ? 'Post to a class'
                    : 'New Announcement',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 16),
                Text('Who sees this', style: Theme.of(dialogContext).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Announcements are notices, not private messages — this '
                  'decides who they are shown to, not who could find them.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (byClass)
                  // One chip per class this teacher is assigned to.
                  // Advisory is marked, because the adviser's own class
                  // is what they mean most of the time.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: classOptions
                        .map(
                          (c) => FilterChip(
                            avatar: c.isAdviser ? const Icon(Icons.star, size: 16) : null,
                            label: Text(
                              c.isAdviser ? '${c.section} (advisory)' : c.section,
                            ),
                            selected: selectedSections.contains(c.section),
                            onSelected: (on) => setState(() {
                              if (on) {
                                selectedSections.add(c.section);
                              } else {
                                selectedSections.remove(c.section);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  )
                else
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Everyone')),
                      ButtonSegment(value: false, label: Text('Choose roles')),
                    ],
                    selected: {toEveryone},
                    onSelectionChanged: (s) => setState(() {
                      toEveryone = s.first;
                      // Reaching for "choose roles" with nothing chosen
                      // would post to nobody, so start from the common case.
                      if (!toEveryone && selectedRoles.isEmpty) {
                        selectedRoles.addAll(AnnouncementAudience.staffOnly.roles);
                      }
                    }),
                  ),
                if (byClass && selectedSections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Pick at least one class, or this reaches nobody.',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                    ),
                  ),
                if (byClass && selectedSections.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Everyone in ${selectedSections.join(", ")} sees this — the '
                      'students, their parents, and the other teachers who take '
                      'them.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                if (!byClass && !toEveryone) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: UserRole.values
                        .where((r) => !r.isPlatformLevel)
                        .map(
                          (r) => FilterChip(
                            label: Text(r.displayName),
                            selected: selectedRoles.contains(r.value),
                            onSelected: (on) => setState(() {
                              if (on) {
                                selectedRoles.add(r.value);
                              } else {
                                selectedRoles.remove(r.value);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  if (selectedRoles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Pick at least one role, or this reaches nobody.',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
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
              onPressed: (byClass ? selectedSections.isEmpty : (!toEveryone && selectedRoles.isEmpty))
                  ? null
                  : () async {
                      final audience = byClass
                          ? AnnouncementAudience.forSections(selectedSections)
                          : toEveryone
                              ? AnnouncementAudience.everyone
                              : AnnouncementAudience(
                                  all: false, roles: selectedRoles.toList());
                      final notifier = ref.read(directorActionControllerProvider.notifier);
                      final success = isEdit
                          ? await notifier.updateAnnouncement(
                              announcementId: existing.id,
                              title: titleController.text,
                              body: bodyController.text,
                              audience: audience,
                              pinned: pinned,
                            )
                          : await notifier.createAnnouncement(
                              title: titleController.text,
                              body: bodyController.text,
                              audience: audience,
                              pinned: pinned,
                            );
                      if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                    },
              child: Text(isEdit ? 'Save' : 'Post'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets an author see the list as any one role sees it -- how they check
/// a notice actually reached the people it was for, before somebody
/// misses a typhoon suspension because it went out to staff only.
class _AudienceFilterBar extends StatelessWidget {
  final UserRole? selected;
  final ValueChanged<UserRole?> onChanged;

  const _AudienceFilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final roles = UserRole.values.where((r) => !r.isPlatformLevel).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
            avatar: selected == null ? const Icon(Icons.check, size: 18) : null,
          ),
          const SizedBox(width: 8),
          ...roles.map(
            (r) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(r.displayName),
                selected: selected == r,
                onSelected: (on) => onChanged(on ? r : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool canAuthor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AnnouncementCard({
    required this.announcement,
    required this.canAuthor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = announcement;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (a.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin, size: 16, color: Colors.orange),
                  ),
                Expanded(child: Text(a.title, style: theme.textTheme.titleMedium)),
                // Read-only for everyone who cannot post -- which is what
                // firestore.rules would enforce anyway, but a button that
                // only ever produces a permission error is worse than no
                // button.
                if (canAuthor) RowActionsMenu(onEdit: onEdit, onDelete: onDelete),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.body),
            const SizedBox(height: 8),
            Row(
              children: [
                // Only authors see the targeting. To everyone else it is
                // noise: they are looking at their own list, so of course
                // it is addressed to them.
                if (canAuthor) ...[
                  Icon(Icons.groups_outlined, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      a.audience.label,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    '${a.createdByName} · ${_dateFormat.format(a.createdAt)}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
