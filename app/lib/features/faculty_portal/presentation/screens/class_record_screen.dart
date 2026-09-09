import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/combo_field.dart';
import '../../domain/entities/class_assessment.dart';
import '../../domain/entities/grading_scheme.dart';
import '../../domain/entities/quarterly_grade.dart';
import '../controllers/faculty_controller.dart';
import '../../domain/entities/coursework_item.dart';

/// The four quarters, named the way the report card names them.
const _terms = ['1st Quarter', '2nd Quarter', '3rd Quarter', '4th Quarter'];

/// The class record: the screen a teacher actually keeps grades in.
///
/// Before this, marking a class of forty meant opening a dialog per
/// child, per piece of work, and typing the student, the term, the
/// component and both numbers each time. Teachers do not do that; they
/// keep a spreadsheet and type the totals in at the end, which is the
/// thing this module exists to replace.
///
/// So: one piece of work is one column, the class is the rows, and the
/// teacher types down the column and saves once. Every mark lands
/// against the piece of work it belongs to, so entering a corrected
/// score replaces the wrong one instead of adding to it — which is what
/// the old path did, silently, by summing both.
///
/// The arithmetic is shown, not just the answer. Each component's total,
/// its percentage, the weight it carries and what that contributes, then
/// the sum and the transmuted grade. A teacher who cannot see how the
/// number was reached keeps the spreadsheet.
class ClassRecordScreen extends ConsumerStatefulWidget {
  const ClassRecordScreen({super.key});

  @override
  ConsumerState<ClassRecordScreen> createState() => _ClassRecordScreenState();
}

class _ClassRecordScreenState extends ConsumerState<ClassRecordScreen> {
  final _subjectController = TextEditingController();
  final _sectionController = TextEditingController();
  String _term = _terms[0];
  GradeQuery? _query;
  bool _working = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    final record = _query == null ? null : ref.watch(classRecordProvider(_query!));

    return Scaffold(
      appBar: AppBar(title: const Text('Class Record')),
      floatingActionButton: _query == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _working ? null : () => _showAssessmentForm(_query!),
              icon: const Icon(Icons.add),
              label: const Text('Add a piece of work'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_working) const LinearProgressIndicator(),
          _picker(),
          const SizedBox(height: 12),
          if (_query == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Pick a subject, a section and a quarter.')),
            )
          else if (record == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _WeightsCard(
              record: record,
              onEdit: () => _showWeightsForm(_query!, record),
            ),
            const SizedBox(height: 12),
            if (record.assessments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nothing has been given out in this quarter yet. Add a quiz, '
                  'a performance task or the exam, then type the marks down '
                  'the class in one go.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else ...[
              _Summary(record: record),
              const SizedBox(height: 12),
              Text('The pieces of work', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Tap one to type the marks down the class.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final assessment in record.assessments)
                _AssessmentTile(
                  assessment: assessment,
                  marked: record.rows
                      .where((r) => r.marks.containsKey(assessment.id))
                      .length,
                  total: record.rows.length,
                  onMark: () => _showMarkSheet(_query!, record, assessment),
                  onEdit: () => _showAssessmentForm(_query!, existing: assessment),
                  onDelete: () => _confirmDelete(assessment, record),
                ),
              const SizedBox(height: 20),
              Text('Where each grade comes from', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final row in record.rows)
                _StudentRow(row: row, assessments: record.assessments),
            ],
          ],
        ],
      ),
    );
  }

  Widget _picker() {
    final coursework =
        ref.watch(myCourseworkStreamProvider).valueOrNull ?? const <CourseworkItem>[];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ComboField(
                controller: _subjectController,
                label: 'Subject',
                suggestions: coursework.map((c) => c.subject).toList(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ComboField(
                controller: _sectionController,
                label: 'Section',
                suggestions: coursework.map((c) => c.section).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _term,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Quarter'),
                items: [
                  for (final term in _terms)
                    DropdownMenuItem(value: term, child: Text(term)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _term = value;
                    // The record is per quarter. Reloading rather than
                    // leaving the old one on screen matters: a record
                    // labelled Q2 showing Q1's marks is the bug this
                    // screen replaced.
                    if (_query != null) _query = _queryNow();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (_subjectController.text.trim().isEmpty ||
                    _sectionController.text.trim().isEmpty) {
                  return;
                }
                setState(() => _query = _queryNow());
              },
              child: const Text('Open'),
            ),
          ],
        ),
      ],
    );
  }

  GradeQuery _queryNow() => GradeQuery(
        subject: _subjectController.text.trim(),
        section: _sectionController.text.trim(),
        term: _term,
      );

  /// Deleting a column changes every student's grade in that component,
  /// so the dialog says how many marks go with it before it asks.
  ///
  /// The count is the whole point. "Delete Quiz 1?" is a question about a
  /// title; "Delete Quiz 1 and the 32 marks recorded against it?" is a
  /// question about children's grades, and they are not the same
  /// question. A teacher who is not told finds out from a parent.
  Future<void> _confirmDelete(ClassAssessment assessment, ClassRecord record) async {
    final marks =
        record.rows.where((r) => r.marks.containsKey(assessment.id)).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${assessment.title}"?'),
        content: Text(
          marks == 0
              ? 'Nothing has been marked against it yet, so no grade changes.'
              : 'The $marks mark${marks == 1 ? '' : 's'} recorded against it '
                  'will go too, and every one of those students\' '
                  '${assessment.component.displayLabel} score will change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final removed = await ref
        .read(facultyActionControllerProvider.notifier)
        .deleteClassAssessment(assessment.id);
    if (!mounted) return;
    setState(() => _working = false);
    if (removed != null) {
      _say(removed == 0
          ? 'Deleted "${assessment.title}".'
          : 'Deleted "${assessment.title}" and $removed '
              'mark${removed == 1 ? '' : 's'}.');
    }
  }

  Future<void> _showAssessmentForm(GradeQuery query,
      {ClassAssessment? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final maxController =
        TextEditingController(text: existing == null ? '' : _trim(existing.maxScore));
    var component = existing?.component ?? GradingComponent.writtenWork;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add a piece of work' : 'Edit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'What is it?',
                    hintText: 'Quiz 1, Long test, Group report',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GradingComponent>(
                  initialValue: component,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Counts towards'),
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
                  controller: maxController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Marked out of'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    setState(() => _working = true);
    final result =
        await ref.read(facultyActionControllerProvider.notifier).saveClassAssessment(
              assessmentId: existing?.id,
              subject: query.subject,
              section: query.section,
              term: query.term!,
              title: titleController.text,
              component: component,
              // -1 rather than 0: zero is refused with "has to be more
              // than zero", which is a true sentence about the wrong
              // problem when the box was left empty.
              maxScore: double.tryParse(maxController.text.trim()) ?? -1,
            );
    if (!mounted) return;
    setState(() => _working = false);
    if (result == null) return;
    if (result.marksOverMax.isNotEmpty) {
      _say('Saved. ${result.marksOverMax.join(', ')} now have a mark higher '
          'than the new total — worth checking.');
    }
  }

  /// The fast path: one column, the whole class, typed down and saved.
  Future<void> _showMarkSheet(
    GradeQuery query,
    ClassRecord record,
    ClassAssessment assessment,
  ) async {
    final controllers = {
      for (final row in record.rows)
        row.student.id: TextEditingController(
          text: row.marks.containsKey(assessment.id)
              ? _trim(row.marks[assessment.id]!)
              : '',
        ),
    };

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (sheetContext, scrollController) => Column(
            children: [
              ListTile(
                title: Text(assessment.title),
                subtitle: Text(
                  '${assessment.component.displayLabel} · out of '
                  '${_trim(assessment.maxScore)}',
                ),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Save'),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: record.rows.length,
                  itemBuilder: (context, index) {
                    final row = record.rows[index];
                    return ListTile(
                      dense: true,
                      title: Text(row.student.fullName),
                      trailing: SizedBox(
                        width: 96,
                        child: TextField(
                          controller: controllers[row.student.id],
                          textAlign: TextAlign.end,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            isDense: true,
                            // Left blank means "did not sit it", which is
                            // not a zero: the piece of work drops out of
                            // both their score and the total it is over.
                            hintText: '/${_trim(assessment.maxScore)}',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (save != true || !mounted) {
      for (final c in controllers.values) {
        c.dispose();
      }
      return;
    }

    final entries = <ScoreEntry>[];
    for (final row in record.rows) {
      final text = controllers[row.student.id]!.text.trim();
      entries.add(ScoreEntry(
        studentId: row.student.id,
        studentName: row.student.fullName,
        score: text.isEmpty ? null : double.tryParse(text) ?? double.nan,
      ));
    }
    for (final c in controllers.values) {
      c.dispose();
    }

    setState(() => _working = true);
    final result =
        await ref.read(facultyActionControllerProvider.notifier).saveAssessmentScores(
              assessmentId: assessment.id,
              scores: entries,
            );
    if (!mounted) return;
    setState(() => _working = false);
    if (result != null) {
      _say('${result.saved} marked'
          '${result.cleared > 0 ? ', ${result.cleared} left blank' : ''}.');
    }
  }

  Future<void> _showWeightsForm(GradeQuery query, ClassRecord record) async {
    final current = record.weights.weights;
    final ww = TextEditingController(text: _trim(current.writtenWork));
    final pt = TextEditingController(text: _trim(current.performanceTask));
    final qa = TextEditingController(text: _trim(current.quarterlyAssessment));

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What each part counts for'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'These three have to add up to 100. A split that does not is '
                'the one mistake that produces grades which look entirely '
                'plausible and are wrong for the whole class, all quarter.',
              ),
              const SizedBox(height: 12),
              _weightField(ww, 'Written work'),
              const SizedBox(height: 8),
              _weightField(pt, 'Performance tasks'),
              const SizedBox(height: 8),
              _weightField(qa, 'Quarterly assessment'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          if (record.weights.isOverride)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('clear'),
              child: const Text('Use the school scheme'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel' || !mounted) return;

    setState(() => _working = true);
    final ok = await ref.read(facultyActionControllerProvider.notifier).setClassWeights(
          subject: query.subject,
          section: query.section,
          weights: action == 'clear'
              ? null
              : SubjectWeights(
                  label: 'Set for this class',
                  writtenWork: double.tryParse(ww.text.trim()) ?? double.nan,
                  performanceTask: double.tryParse(pt.text.trim()) ?? double.nan,
                  quarterlyAssessment: double.tryParse(qa.text.trim()) ?? double.nan,
                ),
        );
    if (!mounted) return;
    setState(() => _working = false);
    if (ok) {
      _say(action == 'clear'
          ? 'Back to the school scheme.'
          : 'Saved. Every grade in this class is recomputed on it.');
    }
  }

  static Widget _weightField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: '%'),
      );
}

class _WeightsCard extends StatelessWidget {
  final ClassRecord record;
  final VoidCallback onEdit;

  const _WeightsCard({required this.record, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = record.weights.weights;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.percent),
        title: Text(
          'WW ${_trim(w.writtenWork)}% · PT ${_trim(w.performanceTask)}% · '
          'QA ${_trim(w.quarterlyAssessment)}%',
          style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
        ),
        // Where the split came from, always. A grade computed on
        // percentages nobody can see is the spreadsheet this replaces.
        subtitle: Text(
          record.weights.provenance,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
        trailing: TextButton(onPressed: onEdit, child: const Text('Change')),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final ClassRecord record;
  const _Summary({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = record.classAverage;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              average == null ? 'Nothing marked yet' : 'Class average $average',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${record.passing} passing · ${record.failing} below 75 · '
              '${record.assessments.length} pieces of work',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  final ClassAssessment assessment;
  final int marked;
  final int total;
  final VoidCallback onMark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssessmentTile({
    required this.assessment,
    required this.marked,
    required this.total,
    required this.onMark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        title: Text(assessment.title),
        subtitle: Text(
          '${assessment.component.shortLabel} · out of '
          '${_trim(assessment.maxScore)} · $marked of $total marked',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.error,
              onPressed: onDelete,
            ),
            FilledButton.tonal(onPressed: onMark, child: const Text('Marks')),
          ],
        ),
        onTap: onMark,
      ),
    );
  }
}

/// One student, with the whole computation under them.
class _StudentRow extends StatelessWidget {
  final ClassRecordRow row;
  final List<ClassAssessment> assessments;

  const _StudentRow({required this.row, required this.assessments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = row.grade;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        title: Text(row.student.fullName),
        // The working number stays, INC or not. A teacher mid-quarter
        // needs to see where a child stands; what they also need to know
        // is that this one will print INC rather than a grade if the
        // quarter closes with a component still empty. So: the figure,
        // and the flag beside it.
        subtitle: Text(
          grade.hasWork
              ? grade.isIncomplete
                  ? 'Incomplete · no '
                      '${grade.missingComponents.map((c) => c.shortLabel).join(' or ')} '
                      'yet · working figure ${grade.initialGrade.toStringAsFixed(2)}'
                  : '${gradeDescriptor(grade.finalGrade)} · initial '
                      '${grade.initialGrade.toStringAsFixed(2)}'
              : 'Nothing marked yet',
        ),
        trailing: !grade.hasWork
            ? const Text('—')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${grade.finalGrade}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: grade.isIncomplete
                          ? theme.colorScheme.onSurfaceVariant
                          : isPassing(grade.finalGrade)
                              ? null
                              : theme.colorScheme.error,
                    ),
                  ),
                  if (grade.isIncomplete)
                    Text(
                      'INC',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                ],
              ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grouped by component rather than one flat list, because
                // the component is what the marks are summed into. A
                // teacher checking a percentage has to be able to see the
                // pieces that made it without matching short labels down
                // a column.
                //
                // Every component is here, including the ones with
                // nothing in them. An empty component left out of the
                // breakdown is one nobody can see is empty -- and it is
                // the one that decides whether this is a grade or an INC.
                for (final component in GradingComponent.values)
                  if (grade.componentFor(component).weight > 0)
                    _ComponentBlock(
                      score: grade.componentFor(component),
                      pieces: assessments
                          .where((a) => a.component == component)
                          .toList(),
                      marks: row.marks,
                    ),
                const Divider(height: 20),
                // The working, in the order it happens. A teacher asked
                // why a child got 87 can point at the line.
                for (final line in grade.workingOut)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Text(line, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One component for one student: what it counts for, the pieces of work
/// inside it, and what it contributed.
///
/// Shown even when it is empty. A component with nothing in it is not an
/// absence of information -- it is the reason the grade is provisional,
/// and it needs to be as visible as the ones that are full.
class _ComponentBlock extends StatelessWidget {
  final ComponentScore score;
  final List<ClassAssessment> pieces;
  final Map<String, double> marks;

  const _ComponentBlock({
    required this.score,
    required this.pieces,
    required this.marks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(score.component.displayLabel, style: theme.textTheme.labelLarge),
          // Under the label rather than beside it, and wrapping. On a
          // phone this line is longer than the row is wide, and a teacher
          // reading it on the way to a staff meeting is the whole point
          // of the screen.
          Text(
            score.hasWork
                ? '${_trim(score.raw)} / ${_trim(score.possible)}  ·  '
                    '${score.percentageScore.toStringAsFixed(2)}%  ·  '
                    '${_trim(score.weight)}% of the grade  ·  '
                    'contributes ${score.weightedScore.toStringAsFixed(2)}'
                : 'nothing recorded  ·  ${_trim(score.weight)}% still to come',
            style: score.hasWork
                ? theme.textTheme.bodySmall
                : muted?.copyWith(fontStyle: FontStyle.italic),
          ),
          if (pieces.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text('No piece of work added yet.', style: muted),
            ),
          for (final piece in pieces)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Row(
                children: [
                  Expanded(child: Text(piece.title, style: muted)),
                  Text(
                    marks.containsKey(piece.id)
                        ? '${_trim(marks[piece.id]!)} / ${_trim(piece.maxScore)}'
                        // Not "0". A child who did not sit it has not
                        // scored nothing, and the arithmetic leaves the
                        // work out of both their score and the total.
                        : 'not sat',
                    style: muted,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();
