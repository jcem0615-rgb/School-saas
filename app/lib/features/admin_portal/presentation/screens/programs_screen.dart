import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/program.dart';
import '../controllers/admin_controller.dart';

/// Admin manages the school's curriculum catalogue here: Senior High
/// strands ("STEM", under the Academic track) and College degree programs
/// ("BS Computer Science", under the College of Engineering).
///
/// Elementary and Junior High have no equivalent -- their gradeLevel and
/// section fields on the student record say everything needed, since they
/// have neither strands nor the many-programs-per-department structure a
/// college does. The two divisions are grouped rather than split into two
/// screens because they are the same record answering the same question
/// at registration: what is this student enrolled in?
class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(programsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Strands & Programs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
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
                  'No strands or programs yet. Add one so Registrar can enrol '
                  'Senior High and College students.',
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
                  subtitle: Text(
                    '${p.educationLevel.displayLabel} · ${p.code} · ${p.department}',
                  ),
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
    // Fixed once saved: moving a strand into the college catalogue would
    // silently reclassify every student already enrolled in it.
    EducationLevel level = existing?.educationLevel ?? EducationLevel.seniorHigh;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final seniorHigh = level == EducationLevel.seniorHigh;
          return AlertDialog(
        title: Text(isEdit
            ? 'Edit ${existing.educationLevel.programLabel}'
            : 'New Strand or Program'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEdit) ...[
                SegmentedButton<EducationLevel>(
                  segments: const [
                    ButtonSegment(
                      value: EducationLevel.seniorHigh,
                      label: Text('Senior High'),
                    ),
                    ButtonSegment(
                      value: EducationLevel.college,
                      label: Text('College'),
                    ),
                  ],
                  selected: {level},
                  onSelectionChanged: (s) => setState(() => level = s.first),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: seniorHigh ? 'Strand Name' : 'Program Name',
                  hintText: seniorHigh
                      ? 'e.g. Science, Technology, Engineering and Mathematics'
                      : 'e.g. BS Computer Science',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: InputDecoration(
                  labelText: 'Code',
                  hintText: seniorHigh ? 'e.g. STEM' : 'e.g. BSCS',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: departmentController,
                decoration: InputDecoration(
                  labelText: seniorHigh ? 'Track' : 'Department',
                  hintText: seniorHigh
                      ? 'e.g. Academic'
                      : 'e.g. College of Engineering',
                  border: const OutlineInputBorder(),
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
                      educationLevel: level,
                    );
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(isEdit ? 'Save Changes' : 'Save'),
          ),
        ],
          );
        },
      ),
    );
  }
}
