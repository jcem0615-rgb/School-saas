import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/user_roles.dart';
import '../controllers/admin_controller.dart';

class TeacherAssignmentsScreen extends ConsumerWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(teacherAssignmentsStreamProvider);
    final employeesAsync = ref.watch(employeesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Assignment')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref, employeesAsync.valueOrNull ?? []),
        icon: const Icon(Icons.add),
        label: const Text('Assign'),
      ),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load assignments: $err')),
        data: (assignments) {
          if (assignments.isEmpty) {
            return const Center(child: Text('No teacher assignments yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: assignments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final a = assignments[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text('${a.subject} · ${a.section}'),
                  subtitle: Text('${a.teacherName} · SY ${a.schoolYear}'),
                  leading: const Icon(Icons.school_outlined),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref, List employees) async {
    final faculty = employees.where((e) => e.role == UserRole.faculty).toList();
    final subjectController = TextEditingController();
    final sectionController = TextEditingController();
    final yearController = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().year + 1}');
    dynamic selectedTeacher = faculty.isNotEmpty ? faculty.first : null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('New Teacher Assignment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (faculty.isEmpty)
                  const Text('No faculty members found. Add one under Employee Management first.')
                else
                  DropdownButtonFormField<dynamic>(
                    value: selectedTeacher,
                    decoration: const InputDecoration(labelText: 'Teacher', border: OutlineInputBorder()),
                    items: faculty
                        .map((f) => DropdownMenuItem(value: f, child: Text(f.fullName as String)))
                        .toList(),
                    onChanged: (v) => setState(() => selectedTeacher = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sectionController,
                  decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearController,
                  decoration: const InputDecoration(labelText: 'School Year', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: selectedTeacher == null
                  ? null
                  : () async {
                      final success = await ref.read(adminActionControllerProvider.notifier).createTeacherAssignment(
                            teacherId: selectedTeacher.uid as String,
                            teacherName: selectedTeacher.fullName as String,
                            subject: subjectController.text,
                            section: sectionController.text,
                            schoolYear: yearController.text,
                          );
                      if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
