import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/grade.dart';
import '../controllers/faculty_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  final _subjectController = TextEditingController();
  final _sectionController = TextEditingController();
  GradeQuery? _activeQuery;

  @override
  void dispose() {
    _subjectController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradesAsync =
        _activeQuery != null ? ref.watch(gradesStreamProvider(_activeQuery!)) : null;

    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grade Submission'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Export / Import',
            onPressed: () => _showTransfer(context, ref),
          ),
        ],
      ),
      floatingActionButton: _activeQuery == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showSubmitDialog(context, ref, _activeQuery!),
              icon: const Icon(Icons.add),
              label: const Text('Submit Grade'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ComboField(
                    controller: _subjectController,
                    label: 'Subject',
                    suggestions: (ref.watch(myCourseworkStreamProvider).valueOrNull ??
                            const <CourseworkItem>[])
                        .map((c) => c.subject)
                        .toList(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ComboField(
                    controller: _sectionController,
                    label: 'Section',
                    suggestions: (ref.watch(myCourseworkStreamProvider).valueOrNull ??
                            const <CourseworkItem>[])
                        .map((c) => c.section)
                        .toList(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_subjectController.text.trim().isEmpty || _sectionController.text.trim().isEmpty) return;
                    setState(() => _activeQuery = GradeQuery(
                          subject: _subjectController.text.trim(),
                          section: _sectionController.text.trim(),
                        ));
                  },
                  child: const Text('Load'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _activeQuery == null
                ? const Center(child: Text('Pick a subject and section, then tap Load.'))
                : Consumer(
                    builder: (context, ref, _) {
                      // The roster drives the list, not the grades: a teacher
                      // needs to see who has NOT been graded yet, which a
                      // grades-only list can never show.
                      final rosterAsync =
                          ref.watch(sectionRosterProvider(_activeQuery!.section));
                      final grades =
                          ref.watch(gradesStreamProvider(_activeQuery!)).valueOrNull ??
                              const <Grade>[];

                      return rosterAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Failed to load roster: $err')),
                        data: (roster) {
                          if (roster.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No students found in ${_activeQuery!.section}.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: roster.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final student = roster[index];
                              final theirs = grades
                                  .where((g) => g.studentId == student.id)
                                  .toList()
                                ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
                              final latest = theirs.firstOrNull;

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(student.firstName.characters.first),
                                  ),
                                  title: Text(student.fullName),
                                  subtitle: Text(
                                    latest == null
                                        ? 'No grade yet · ${student.studentNumber}'
                                        : '${latest.term} · ${_dateFormat.format(latest.submittedAt)}',
                                  ),
                                  trailing: latest == null
                                      ? const Chip(
                                          label: Text('Ungraded'),
                                          visualDensity: VisualDensity.compact,
                                        )
                                      : Text(
                                          '${latest.score.toStringAsFixed(1)} / '
                                          '${latest.maxScore.toStringAsFixed(1)}',
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                  onTap: () => _showSubmitDialog(
                                    context,
                                    ref,
                                    _activeQuery!,
                                    student: student,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Export only. A grade import would need to resolve student names to
  /// ids and re-run the scope check firestore.rules applies per student,
  /// so posting marks stays on the roster screen where the teacher is
  /// looking at the actual student they are grading.
  void _showTransfer(BuildContext context, WidgetRef ref) {
    final query = _activeQuery;
    final grades = query == null
        ? const <Grade>[]
        : (ref.read(gradesStreamProvider(query)).valueOrNull ?? const <Grade>[]);
    showExportImportSheet(
      context: context,
      label: 'Grades',
      headers: const ['Student', 'Subject', 'Section', 'Term', 'Score', 'Max Score', 'Remarks'],
      rows: () => grades
          .map((g) => [
                g.studentName,
                g.subject,
                g.section,
                g.term,
                g.score.toStringAsFixed(1),
                g.maxScore.toStringAsFixed(1),
                g.remarks ?? '',
              ])
          .toList(),
    );
  }

  Future<void> _showSubmitDialog(
    BuildContext context,
    WidgetRef ref,
    GradeQuery query, {
    StudentSummary? student,
  }) async {
    // Prefilled and read-only when opened from the roster: the teacher
    // picked the student by tapping them, so retyping the id is only an
    // opportunity to mis-key it onto someone else's record.
    final studentIdController = TextEditingController(text: student?.id ?? '');
    final studentNameController = TextEditingController(text: student?.fullName ?? '');
    final termController = TextEditingController(text: 'Q1');
    final scoreController = TextEditingController();
    final maxScoreController = TextEditingController(text: '100');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit Grade'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: studentIdController,
                readOnly: student != null,
                decoration: const InputDecoration(labelText: 'Student ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: studentNameController,
                readOnly: student != null,
                decoration: const InputDecoration(labelText: 'Student Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: termController,
                decoration: const InputDecoration(labelText: 'Term (e.g. Q1)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Score'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Score'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final success = await ref.read(facultyActionControllerProvider.notifier).submitGrade(
                    studentId: studentIdController.text.trim(),
                    studentName: studentNameController.text.trim(),
                    subject: query.subject,
                    section: query.section,
                    term: termController.text.trim(),
                    score: double.tryParse(scoreController.text) ?? -1,
                    maxScore: double.tryParse(maxScoreController.text) ?? 0,
                  );
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
