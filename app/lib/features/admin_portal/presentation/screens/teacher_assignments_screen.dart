import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/data_transfer/csv.dart';
import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../domain/entities/teacher_assignment.dart';
import '../controllers/admin_controller.dart';

class TeacherAssignmentsScreen extends ConsumerWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(teacherAssignmentsStreamProvider);
    final employeesAsync = ref.watch(employeesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Assignment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Export / Import',
            onPressed: () => _showTransfer(context, ref, employeesAsync.valueOrNull ?? []),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref, employeesAsync.valueOrNull ?? []),
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
                  trailing: RowActionsMenu(
                    onEdit: () => _showEditor(
                        context, ref, employeesAsync.valueOrNull ?? [], existing: a),
                    onDelete: () => _confirmDelete(context, ref, a),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Assignments are importable: creating one is an ordinary Firestore
  /// write that firestore.rules already gates on director/principal/admin,
  /// so a bulk import goes through exactly the same check as the form.
  /// The teacher is matched by email rather than uid, since a uid is not
  /// something anyone can type into a spreadsheet.
  void _showTransfer(BuildContext context, WidgetRef ref, List employees) {
    final assignments = ref.read(teacherAssignmentsStreamProvider).valueOrNull ?? const <TeacherAssignment>[];
    final faculty = employees.where((e) => e.role == UserRole.faculty).toList();

    showExportImportSheet(
      context: context,
      label: 'Teacher Assignments',
      headers: const ['Teacher Email', 'Teacher Name', 'Subject', 'Section', 'School Year'],
      rows: () => assignments.map((a) {
        final teacher = faculty.where((e) => e.uid == a.teacherId).firstOrNull;
        return [
          (teacher?.email as String?) ?? '',
          a.teacherName,
          a.subject,
          a.section,
          a.schoolYear,
        ];
      }).toList(),
      parseRow: (row, rowNumber) {
        final email = row[0].trim().toLowerCase();
        final subject = row[2].trim();
        final section = row[3].trim();
        final schoolYear = row[4].trim();

        if (subject.isEmpty || section.isEmpty) {
          return ImportIssue(rowNumber, 'Subject and section are required.');
        }
        final teacher = faculty.where((e) => (e.email as String).toLowerCase() == email).firstOrNull;
        if (teacher == null) {
          return ImportIssue(rowNumber, 'No faculty account with email "$email".');
        }
        final duplicate = assignments.any((a) =>
            a.teacherId == teacher.uid &&
            a.subject == subject &&
            a.section == section &&
            a.schoolYear == schoolYear);
        if (duplicate) {
          return ImportIssue(rowNumber, '$subject / $section is already assigned to this teacher.');
        }
        return _AssignmentImportRow(
          teacherId: teacher.uid as String,
          teacherName: teacher.fullName as String,
          subject: subject,
          section: section,
          schoolYear: schoolYear,
        );
      },
      onImport: (records) async {
        final notifier = ref.read(adminActionControllerProvider.notifier);
        var created = 0;
        for (final r in records.cast<_AssignmentImportRow>()) {
          final ok = await notifier.createTeacherAssignment(
            teacherId: r.teacherId,
            teacherName: r.teacherName,
            subject: r.subject,
            section: r.section,
            schoolYear: r.schoolYear,
          );
          if (ok) created++;
        }
        return created;
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, TeacherAssignment a) async {
    final ok = await confirmDelete(
      context,
      itemLabel: 'assignment',
      detail: '${a.subject} · ${a.section} (${a.teacherName})',
    );
    if (!ok) return;
    await ref.read(adminActionControllerProvider.notifier).deleteTeacherAssignment(a.id);
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref,
    List employees, {
    TeacherAssignment? existing,
  }) async {
    final isEdit = existing != null;
    final faculty = employees.where((e) => e.role == UserRole.faculty).toList();
    final subjectController = TextEditingController(text: existing?.subject ?? '');
    final sectionController = TextEditingController(text: existing?.section ?? '');
    final yearController = TextEditingController(
        text: existing?.schoolYear ?? '${DateTime.now().year}-${DateTime.now().year + 1}');
    // On edit, preselect the assignment's own teacher rather than the
    // first in the list, so saving without touching the dropdown cannot
    // silently reassign the subject to someone else.
    dynamic selectedTeacher = isEdit
        ? faculty.where((e) => e.uid == existing.teacherId).firstOrNull ??
            (faculty.isNotEmpty ? faculty.first : null)
        : (faculty.isNotEmpty ? faculty.first : null);

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
                    isExpanded: true,
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
                      final notifier = ref.read(adminActionControllerProvider.notifier);
                      final success = isEdit
                          ? await notifier.updateTeacherAssignment(
                              assignmentId: existing.id,
                              teacherId: selectedTeacher.uid as String,
                              teacherName: selectedTeacher.fullName as String,
                              subject: subjectController.text,
                              section: sectionController.text,
                              schoolYear: yearController.text,
                            )
                          : await notifier.createTeacherAssignment(
                              teacherId: selectedTeacher.uid as String,
                              teacherName: selectedTeacher.fullName as String,
                              subject: subjectController.text,
                              section: sectionController.text,
                              schoolYear: yearController.text,
                            );
                      if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                    },
              child: Text(isEdit ? 'Save Changes' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One validated row from an assignment import, resolved to a real
/// teacher before anything is written.
class _AssignmentImportRow {
  final String teacherId;
  final String teacherName;
  final String subject;
  final String section;
  final String schoolYear;

  const _AssignmentImportRow({
    required this.teacherId,
    required this.teacherName,
    required this.subject,
    required this.section,
    required this.schoolYear,
  });
}
