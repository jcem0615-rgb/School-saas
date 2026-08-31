import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/grade.dart';
import '../../domain/entities/grading_scheme.dart';
import '../../domain/entities/quarterly_grade.dart';
import '../controllers/faculty_controller.dart';
import '../import/grade_import.dart';

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

                              // The weighted grade for the term the last
                              // mark was posted in -- which is the one
                              // the teacher is working on. A running
                              // total of raw scores was never the number
                              // that goes on a report card, and a teacher
                              // who cannot see the real one keeps a
                              // spreadsheet that computes it.
                              final scheme =
                                  ref.watch(gradingSchemeProvider).valueOrNull;
                              final computed = (latest == null || scheme == null)
                                  ? null
                                  : computeQuarterlyGrade(
                                      subject: _activeQuery!.subject,
                                      term: latest.term,
                                      grades: theirs
                                          .where((g) => g.term == latest.term),
                                      scheme: scheme,
                                    );

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
                                        : _componentSummary(latest, computed),
                                  ),
                                  trailing: latest == null || computed == null
                                      ? const Chip(
                                          label: Text('Ungraded'),
                                          visualDensity: VisualDensity.compact,
                                        )
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${computed.finalGrade}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: isPassing(computed.finalGrade)
                                                        ? null
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                  ),
                                            ),
                                            Text(
                                              latest.term,
                                              style:
                                                  Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
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

  /// What is behind the number, in one line.
  ///
  /// Says which components are still empty, because a grade computed from
  /// written work alone is not the grade the child will end the quarter
  /// with, and a teacher reading 92 in week two should know that.
  static String _componentSummary(Grade latest, QuarterlyGrade? computed) {
    final when = _dateFormat.format(latest.submittedAt);
    if (computed == null) return '${latest.term} · $when';
    final missing = computed.missingComponents;
    if (missing.isEmpty) {
      return '${computed.weights.label} · all three components · $when';
    }
    return '${computed.weights.label} · no '
        '${missing.map((c) => c.shortLabel).join(' or ')} yet · $when';
  }

  /// Export, and import for the class currently on screen.
  ///
  /// Subject and section are not columns in the import: the teacher has
  /// already chosen them here, and a file that could name a different
  /// section would be a way of posting marks to a class the roster check
  /// was never run against. That is also why nothing can be imported
  /// before a class is chosen -- there is no roster to resolve names
  /// against, so every row would be unattributable.
  void _showTransfer(BuildContext context, WidgetRef ref) {
    final query = _activeQuery;
    final grades = query == null
        ? const <Grade>[]
        : (ref.read(gradesStreamProvider(query)).valueOrNull ?? const <Grade>[]);
    final roster = query == null
        ? const <StudentSummary>[]
        : (ref.read(sectionRosterProvider(query.section)).valueOrNull ??
            const <StudentSummary>[]);
    // Per file: the same student twice for one term has to be caught
    // across the whole file to be caught at all.
    final seen = <String>{};

    // A class has to be chosen, and its roster has to have arrived. With
    // an empty roster every name would be reported as "not in this
    // section", which reads as the file being wrong when the truth is
    // that the class was never loaded.
    final canImport = query != null && roster.isNotEmpty;

    showExportImportSheet(
      context: context,
      label: 'Grades',
      headers: const [
        'Student', 'Subject', 'Section', 'Term', 'Component', 'Score',
        'Max Score', 'Remarks',
      ],
      importHeaders: const ['Student', 'Term', 'Component', 'Score', 'Max Score', 'Remarks'],
      importNote: !canImport
          ? null
          : 'Marks are posted to ${query.subject} · ${query.section} — the '
              'class chosen above — so the file does not carry Subject or '
              'Section. Name students as they appear on the class list, or '
              'by student number. Component is Written Work, Performance '
              'Tasks or Quarterly Assessment (WW, PT, QA) and decides how '
              'the mark is weighted; blank means written work. Leave Max '
              'Score blank for a mark out of 100.',
      importUnavailableNote: query == null
          ? 'Choose a subject and section above first. Marks are posted to '
              'the class on screen, and students are matched against that '
              'class list.'
          : 'The class list for ${query.section} has not loaded yet. Marks '
              'are matched against it, so importing without it would '
              'attribute every row to nobody.',
      rows: () => grades
          .map((g) => [
                g.studentName,
                g.subject,
                g.section,
                g.term,
                g.component.displayLabel,
                g.score.toStringAsFixed(1),
                g.maxScore.toStringAsFixed(1),
                g.remarks ?? '',
              ])
          .toList(),
      parseRow: !canImport
          ? null
          : (row, rowNumber) => GradeImport.parseRow(
                row: row,
                rowNumber: rowNumber,
                roster: roster,
                existing: grades,
                seen: seen,
              ),
      onImport: !canImport
          ? null
          : (records) async {
              final controller = ref.read(facultyActionControllerProvider.notifier);
              // Counted as they land rather than assumed from the row
              // count: a teacher told "36 imported" when nine were
              // written has no reason to look again.
              var imported = 0;
              for (final r in records.cast<GradeImportRow>()) {
                final ok = await controller.submitGrade(
                  studentId: r.studentId,
                  studentName: r.studentName,
                  subject: query.subject,
                  section: query.section,
                  term: r.term,
                  component: r.component,
                  score: r.score,
                  maxScore: r.maxScore,
                  remarks: r.remarks,
                );
                if (ok) imported++;
              }
              return imported;
            },
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
    var component = GradingComponent.writtenWork;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
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
              // Which of the three the mark counts towards. Not optional
              // and not a free-text field: a score filed under nothing
              // cannot be weighted, and the whole quarterly grade rests
              // on this one choice being right.
              DropdownButtonFormField<GradingComponent>(
                initialValue: component,
                // Without this the dropdown takes its width from the
                // longest label -- "Quarterly Assessment" -- and pushes
                // the dialog past the edge of a phone.
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Component'),
                items: [
                  for (final c in GradingComponent.values)
                    DropdownMenuItem(value: c, child: Text(c.displayLabel)),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => component = value);
                },
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
                    component: component,
                    score: double.tryParse(scoreController.text) ?? -1,
                    maxScore: double.tryParse(maxScoreController.text) ?? 0,
                  );
              if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
      ),
    );
  }
}
