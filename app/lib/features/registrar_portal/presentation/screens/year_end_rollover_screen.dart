import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../faculty_portal/presentation/controllers/faculty_controller.dart'
    show gradingSchemeProvider;
import '../../domain/entities/promotion.dart';
import '../../domain/entities/student_summary.dart';
import '../../domain/usecases/rollover_usecases.dart';
import '../controllers/registrar_controller.dart';

/// Moving a school up a year.
///
/// The least reversible thing in this system, so it is built as a plan
/// somebody reads rather than a button that does it. The marks produce a
/// recommendation per student; every row can be changed; nothing is
/// written until the registrar presses the button and confirms what they
/// are about to do.
///
/// One section at a time. It is how a registrar works -- through class
/// lists they recognise -- and a screen that asked somebody to check nine
/// hundred rows in one sitting is a screen that gets scrolled past.
class YearEndRolloverScreen extends ConsumerStatefulWidget {
  const YearEndRolloverScreen({super.key});

  @override
  ConsumerState<YearEndRolloverScreen> createState() => _YearEndRolloverScreenState();
}

class _YearEndRolloverScreenState extends ConsumerState<YearEndRolloverScreen> {
  final _sectionController = TextEditingController();
  late final _schoolYearController =
      TextEditingController(text: currentSchoolYear(DateTime.now()));

  List<_Row>? _rows;
  bool _working = false;

  @override
  void dispose() {
    _sectionController.dispose();
    _schoolYearController.dispose();
    super.dispose();
  }

  Future<void> _drawUpPlan(List<StudentSummary> allStudents) async {
    final section = _sectionController.text.trim();
    if (section.isEmpty) {
      _say('Choose a section first.');
      return;
    }
    final scheme = ref.read(gradingSchemeProvider).valueOrNull;
    if (scheme == null) {
      _say('The grading scheme has not loaded yet. Try again in a moment.');
      return;
    }

    final inSection = allStudents
        .where((s) => s.section == section && s.status == StudentStatus.enrolled)
        .toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));

    if (inSection.isEmpty) {
      _say('No enrolled students in $section.');
      return;
    }

    setState(() => _working = true);
    final result = await BuildRolloverPlanUseCase(ref.read(registrarRepositoryProvider))(
      section: inSection,
      scheme: scheme,
      // What the school runs, read off the roster rather than a setting
      // somebody has to keep current -- it decides whether a Grade 10
      // graduates or moves into Senior High.
      divisionsInUse: {for (final s in allStudents) s.educationLevel},
    );
    if (!mounted) return;

    final already = await ref
        .read(registrarRepositoryProvider)
        .fetchRolledOverStudentIds(_schoolYearController.text.trim());
    if (!mounted) return;

    setState(() {
      _working = false;
      _rows = switch (result) {
        Success(:final value) => [
            for (final candidate in value)
              _Row(candidate: candidate, alreadyDone: already.contains(candidate.student.id)),
          ],
        _ => null,
      };
    });
    if (_rows == null) _say('Could not read this section\'s marks.');
  }

  /// The rows a run would actually act on.
  ///
  /// "No decision" rows are left out: a promotion record is what marks a
  /// student as done for the year, so writing one for somebody nobody
  /// has decided about would lock them out of the rollover for good. A
  /// registrar running this before the last marks are in has to be able
  /// to come back for them.
  List<_Row> get _actionable => (_rows ?? const <_Row>[])
      .where((r) => !r.alreadyDone && r.outcome != PromotionOutcome.held)
      .toList();

  Future<void> _run() async {
    final rows = _actionable;
    if (rows.isEmpty) {
      final pending = (_rows ?? const <_Row>[])
          .where((r) => !r.alreadyDone)
          .length;
      _say(pending == 0
          ? 'Every student in this section has already been rolled over.'
          : 'Every student left is marked "No decision". Decide them, or come '
              'back once their marks are in.');
      return;
    }

    final summary = RolloverSummary.of(rows.map((r) => r.outcome));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Roll over ${_sectionController.text.trim()}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.promoted} promoted, ${summary.conditional} for remedial '
              'work, ${summary.retained} retained, ${summary.graduated} '
              'graduating, ${summary.held} left alone.',
            ),
            const SizedBox(height: 12),
            // Said plainly. There is no undo, and a registrar finding
            // that out afterwards is the worst version of this screen.
            const Text(
              'Promoted students move to the year and section on their row, '
              'and graduating students are marked graduated. This cannot be '
              'undone from the app -- putting a student back is a manual '
              'correction on their record.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Roll them over'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final outcome = await ref
        .read(registrarActionControllerProvider.notifier)
        .runYearEndRollover(
          schoolYear: _schoolYearController.text.trim(),
          decisions: [for (final row in rows) row.decision],
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (outcome == null) return; // The listener has already said why.

    setState(() {
      for (final row in rows) {
        row.alreadyDone = true;
      }
    });
    _say(outcome.skipped == 0
        ? '${outcome.applied} students moved into ${outcome.schoolYear}.'
        : '${outcome.applied} students moved. ${outcome.skipped} had already '
            'been done and were left alone.');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studentsAsync = ref.watch(studentsStreamProvider);
    final students = studentsAsync.valueOrNull ?? const <StudentSummary>[];
    // Watched so it has arrived by the time the plan is drawn up.
    ref.watch(gradingSchemeProvider);

    ref.listen(registrarActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    final rows = _rows;

    return Scaffold(
      appBar: AppBar(title: const Text('Year-End Rollover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: ComboField(
                      controller: _sectionController,
                      label: 'Section',
                      suggestions: students
                          .where((s) => s.status == StudentStatus.enrolled)
                          .map((s) => s.section)
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _schoolYearController,
                      decoration: const InputDecoration(labelText: 'School year'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _working ? null : () => _drawUpPlan(students),
                    child: const Text('Draw up'),
                  ),
                ]),
                if (rows != null) ...[
                  const SizedBox(height: 12),
                  _SummaryBar(rows: rows),
                ],
              ],
            ),
          ),
          if (_working) const LinearProgressIndicator(),
          Expanded(
            child: rows == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Pick a section and draw up the plan. Nothing is '
                        'written until you say so.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _RowCard(
                      row: rows[index],
                      onChanged: () => setState(() {}),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: rows == null || _actionable.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _working ? null : _run,
              icon: const Icon(Icons.arrow_upward),
              label: Text('Roll over ${_actionable.length}'),
            ),
      bottomNavigationBar: rows == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Recommendations come from this year\'s grades: every subject '
                'passed is a promotion, one or two failed means remedial '
                'classes first, three or more is a retention. Change any row '
                'you disagree with -- what was recommended is kept alongside '
                'what you decided.',
                style: theme.textTheme.bodySmall,
              ),
            ),
    );
  }
}

/// One student's row, as the registrar has left it.
class _Row {
  final PromotionCandidate candidate;
  bool alreadyDone;

  late PromotionOutcome outcome = candidate.recommended;
  late final TextEditingController gradeLevel =
      TextEditingController(text: candidate.nextGradeLevel ?? '');
  late final TextEditingController section = TextEditingController(
    text: candidate.nextGradeLevel == null
        ? ''
        : nextSectionName(
              section: candidate.student.section,
              fromGradeLevel: candidate.student.gradeLevel,
              toGradeLevel: candidate.nextGradeLevel!,
            ) ??
            '',
  );

  _Row({required this.candidate, this.alreadyDone = false});

  PromotionDecision get decision => PromotionDecision(
        studentId: candidate.student.id,
        studentName: candidate.student.fullName,
        recommended: candidate.recommended,
        outcome: outcome,
        fromGradeLevel: candidate.student.gradeLevel,
        fromSection: candidate.student.section,
        toGradeLevel:
            outcome == PromotionOutcome.promoted ? gradeLevel.text.trim() : '',
        toSection: outcome == PromotionOutcome.promoted ? section.text.trim() : '',
        generalAverage: candidate.generalAverage,
        failedSubjects: candidate.failedSubjects,
      );
}

class _SummaryBar extends StatelessWidget {
  final List<_Row> rows;
  const _SummaryBar({required this.rows});

  @override
  Widget build(BuildContext context) {
    final summary = RolloverSummary.of(rows.map((r) => r.outcome));
    final done = rows.where((r) => r.alreadyDone).length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, '${summary.promoted} promoted'),
        if (summary.conditional > 0) _chip(context, '${summary.conditional} remedial'),
        if (summary.retained > 0) _chip(context, '${summary.retained} retained'),
        if (summary.graduated > 0) _chip(context, '${summary.graduated} graduating'),
        if (summary.held > 0) _chip(context, '${summary.held} no decision'),
        if (done > 0) _chip(context, '$done already done'),
      ],
    );
  }

  Widget _chip(BuildContext context, String label) => Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );
}

class _RowCard extends StatelessWidget {
  final _Row row;
  final VoidCallback onChanged;

  const _RowCard({required this.row, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = row.candidate;
    final departed = row.outcome != candidate.recommended;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: row.alreadyDone
              ? theme.colorScheme.outlineVariant
              : departed
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Opacity(
        opacity: row.alreadyDone ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(candidate.student.fullName,
                            style: theme.textTheme.titleSmall),
                        Text(candidate.reason, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (row.alreadyDone)
                    const Chip(
                      label: Text('Done'),
                      visualDensity: VisualDensity.compact,
                    )
                  else if (candidate.generalAverage != null)
                    Text('${candidate.generalAverage}',
                        style: theme.textTheme.titleMedium),
                ],
              ),
              if (!row.alreadyDone) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<PromotionOutcome>(
                  initialValue: row.outcome,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Decision', isDense: true),
                  items: [
                    for (final outcome in PromotionOutcome.values)
                      DropdownMenuItem(value: outcome, child: Text(outcome.displayLabel)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    row.outcome = value;
                    onChanged();
                  },
                ),
                if (row.outcome == PromotionOutcome.promoted) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: row.gradeLevel,
                        decoration: const InputDecoration(
                          labelText: 'Moves to year',
                          isDense: true,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.section,
                        decoration: const InputDecoration(
                          labelText: 'and section',
                          isDense: true,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                  ]),
                  // The case the domain refuses to guess at: a grade
                  // level with no number in it to advance. A question
                  // rather than a silent blank.
                  if (candidate.nextGradeLevel == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Which year "${candidate.student.gradeLevel}" leads to '
                        'is not something this can work out. Type it in.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
                if (departed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Recommended: ${candidate.recommended.displayLabel}. Your '
                      'decision is kept alongside it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
