import 'package:flutter/material.dart';

/// Confirmation shown before any delete action in the app.
///
/// The wording matters and is deliberately not "permanently delete":
/// nothing in this system is ever hard-deleted. Every collection in
/// firestore.rules sets `allow delete: if false`, so a delete is an update
/// that sets `isDeleted`, and the record stays in the database with its
/// audit history intact. Telling a user their data is gone forever when it
/// is recoverable would be a lie in the more alarming direction.
Future<bool> confirmDelete(
  BuildContext context, {
  required String itemLabel,
  String? detail,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.delete_outline),
      title: Text('Delete $itemLabel?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail != null) ...[
            Text(detail),
            const SizedBox(height: 12),
          ],
          Text(
            'It will be removed from this list. The record is retained and '
            'the deletion is recorded in the audit trail.',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The overflow menu used on every editable list row, so edit/delete look
/// and behave the same across all nine portals that have them.
class RowActionsMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<PopupMenuEntry<String>> extraActions;
  final void Function(String value)? onExtraAction;

  const RowActionsMenu({
    super.key,
    required this.onEdit,
    required this.onDelete,
    this.extraActions = const [],
    this.onExtraAction,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          default:
            onExtraAction?.call(value);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('Edit'),
          ),
        ),
        ...extraActions,
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
      ],
    );
  }
}
