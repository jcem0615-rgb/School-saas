import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/program.dart';
import '../controllers/admin_controller.dart';

/// Admin manages the college program/course catalog here (e.g. "BS
/// Computer Science", department "College of Engineering"). Elementary
/// and High School have no equivalent -- their "gradeLevel"/"section"
/// fields on the student record are sufficient, since they don't have
/// the many-programs-per-department structure a college does.
class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(programsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('College Programs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Program'),
      ),
      body: programsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load programs: $err')),
        data: (programs) {
          if (programs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No college programs yet. Add one so Registrar can enroll college students.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = programs[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(p.name),
                  subtitle: Text('${p.code} · ${p.department}'),
                  trailing: RowActionsMenu(
                    onEdit: () => _showEditor(context, ref, existing: p),
                    onDelete: () => _confirmDelete(context, ref, p),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Program p) async {
    final ok = await confirmDelete(
      context,
      itemLabel: 'program',
      detail: '${p.name} (${p.code})\n\nStudents already enrolled keep their '
          'program on their own record and are unaffected; this removes the '
          'option from the catalogue.',
    );
    if (!ok) return;
    await ref.read(adminActionControllerProvider.notifier).deleteProgram(p.id);
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, {Program? existing}) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final codeController = TextEditingController(text: existing?.code ?? '');
    final departmentController = TextEditingController(text: existing?.department ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit College Program' : 'New College Program'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Program Name',
                  hintText: 'e.g. BS Computer Science',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. BSCS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: departmentController,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  hintText: 'e.g. College of Engineering',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final notifier = ref.read(adminActionControllerProvider.notifier);
              final success = isEdit
                  ? await notifier.updateProgram(
                      programId: existing.id,
                      name: nameController.text,
                      code: codeController.text,
                      department: departmentController.text,
                    )
                  : await notifier.createProgram(
                      name: nameController.text,
                      code: codeController.text,
                      department: departmentController.text,
                    );
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(isEdit ? 'Save Changes' : 'Save'),
          ),
        ],
      ),
    );
  }
}
