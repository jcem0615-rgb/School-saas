import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/emergency_contact.dart';
import '../controllers/emergency_controller.dart';

/// The numbers to call when something goes wrong.
///
/// One screen for the whole school. Everyone reads it; the admin roles
/// also get the editor here rather than in a separate admin-only screen,
/// so there is no chance of the list a student sees drifting from the
/// list an admin maintains.
const _editorRoles = [UserRole.director, UserRole.principal, UserRole.admin];

class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(emergencyContactsProvider);
    final role = ref.watch(authStateProvider).valueOrNull?.role;
    final canEdit = role != null && _editorRoles.contains(role);

    ref.listen(emergencyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Numbers')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _showEditor(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add number'),
            )
          : null,
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load numbers: $err')),
        data: (contacts) {
          if (contacts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  canEdit
                      ? 'No numbers yet. Add the ones your school posts by the door.'
                      : 'Your school has not published any emergency numbers yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final c = contacts[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.local_phone_outlined),
                  title: Text(c.label),
                  subtitle: Text(
                    c.notes == null ? c.phone : '${c.phone}\n${c.notes}',
                  ),
                  isThreeLine: c.notes != null,
                  trailing: canEdit
                      ? RowActionsMenu(
                          onEdit: () => _showEditor(context, ref, existing: c),
                          onDelete: () => _confirmDelete(context, ref, c),
                        )
                      : const Icon(Icons.call),
                  // The whole row dials, not a small icon. Somebody using
                  // this screen is having a bad day and should not have to
                  // aim.
                  onTap: () => _dial(context, c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _dial(BuildContext context, EmergencyContact contact) async {
    final uri = Uri(scheme: 'tel', path: contact.dialable);
    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      // Desktop browsers often have no dialler. Showing the number is
      // then the useful thing, rather than an error nobody can act on.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Call ${contact.phone}')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, EmergencyContact c) async {
    final ok = await confirmDelete(context, itemLabel: 'number', detail: '${c.label} · ${c.phone}');
    if (!ok) return;
    await ref.read(emergencyActionControllerProvider.notifier).deleteContact(c.id);
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref, {
    EmergencyContact? existing,
  }) async {
    final isEdit = existing != null;
    final labelController = TextEditingController(text: existing?.label ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    final orderController =
        TextEditingController(text: (existing?.sortOrder ?? 99).toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit Number' : 'New Emergency Number'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Who answers',
                  hintText: 'BFP - San Nicolas Fire Station',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Number',
                  hintText: '(043) 555 0161',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Ask for the desk officer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: orderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Order in the list',
                  helperText: 'Lower shows first. Put whoever to call first at the top.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref.read(emergencyActionControllerProvider.notifier).saveContact(
                    contactId: existing?.id,
                    label: labelController.text,
                    phone: phoneController.text,
                    notes: notesController.text,
                    sortOrder: int.tryParse(orderController.text) ?? 99,
                  );
              if (ok && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }
}
