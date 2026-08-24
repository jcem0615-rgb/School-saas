import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data_transfer/open_attachment.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../../registrar_portal/presentation/controllers/registrar_controller.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/coursework_submission.dart';
import '../controllers/faculty_controller.dart';
import 'answer_key_screen.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// What has been handed in for one piece of coursework, and what it is
/// worth.
///
/// Marking happens here, on the work itself, because that is where the
/// evidence is -- a teacher deciding a score wants the answer in front of
/// them, not a separate roster screen. Auto-marked items arrive already
/// scored; the Mark button exists so a teacher can disagree, which is the
/// expected case and not an error condition.
///
/// The Grades flow still owns report-card marks. That is a different
/// record with terms and max scores, and a mark on one piece of work is
/// not the same claim as a subject grade for a quarter.
class SubmissionsScreen extends ConsumerWidget {
  final CourseworkItem item;
  const SubmissionsScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissionsAsync = ref.watch(submissionsForProvider(item.id));

    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Answer key',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AnswerKeyScreen(item: item)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${item.title} · ${item.subject} - ${item.section}',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: submissionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load submissions: $err')),
        data: (submissions) {
          final roster = ref.watch(studentsStreamProvider).valueOrNull ?? const <StudentSummary>[];
          // Who has NOT handed in is the more useful half of this screen
          // and the half a list of submissions cannot show, so the class
          // roll is what the answer is measured against.
          final classList = roster.where((s) => s.section == item.section).toList();
          final submittedIds = submissions.map((s) => s.studentId).toSet();
          final missing = classList.where((s) => !submittedIds.contains(s.id)).toList()
            ..sort((a, b) => a.fullName.compareTo(b.fullName));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Summary(
                submitted: submissions.length,
                missing: missing.length,
                late: submissions.where((s) => s.isLateFor(item)).length,
                autoScored: item.isAutoScored,
                questionCount: item.questionCount,
              ),
              const SizedBox(height: 16),
              if (submissions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Nobody has handed this in yet.')),
                )
              else ...[
                Text('Handed in', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...submissions.map((s) => _SubmissionCard(
                      submission: s,
                      item: item,
                      onGrade: () => _showGradeDialog(context, ref, s),
                    )),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Not yet handed in', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...missing.map(
                  (s) => Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.pending_outlined),
                      title: Text(s.fullName),
                      subtitle: Text(s.studentNumber),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Marking one submission by hand. Overrides whatever the automatic pass
/// produced, and says so -- a teacher disagreeing with the machine is the
/// expected case, not an error condition.
Future<void> _showGradeDialog(
  BuildContext context,
  WidgetRef ref,
  CourseworkSubmission submission,
) async {
  final scoreController = TextEditingController(
    text: submission.effectiveScore?.toString() ?? '',
  );
  final feedbackController = TextEditingController(text: submission.feedback ?? '');

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Mark ${submission.studentName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (submission.autoScore != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Marked automatically at ${submission.autoScore}. Anything '
                  'you enter here replaces that.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: scoreController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Score'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Feedback (optional)',
                alignLabelWithHint: true,
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
            final score = double.tryParse(scoreController.text);
            if (score == null || score < 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Enter a score of zero or more.')),
              );
              return;
            }
            final ok = await ref.read(facultyActionControllerProvider.notifier).gradeSubmission(
                  submissionId: submission.id,
                  score: score,
                  feedback: feedbackController.text.trim().isEmpty
                      ? null
                      : feedbackController.text.trim(),
                );
            if (ok && dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Save mark'),
        ),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  final int submitted;
  final int missing;
  final int late;
  final bool autoScored;
  final int questionCount;

  const _Summary({
    required this.submitted,
    required this.missing,
    required this.late,
    required this.autoScored,
    required this.questionCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.check_circle_outline, size: 16),
          label: Text('$submitted handed in'),
        ),
        Chip(
          avatar: const Icon(Icons.pending_outlined, size: 16),
          label: Text('$missing outstanding'),
        ),
        if (late > 0)
          Chip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text('$late late'),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        if (autoScored)
          Chip(
            avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text('Auto-marked · $questionCount questions'),
          ),
      ],
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final CourseworkSubmission submission;
  final CourseworkItem item;
  final VoidCallback onGrade;

  const _SubmissionCard({
    required this.submission,
    required this.item,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final late = submission.isLateFor(item);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(submission.studentName, style: theme.textTheme.titleSmall),
                ),
                if (late)
                  Chip(
                    label: const Text('Late'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.errorContainer,
                  ),
              ],
            ),
            Text(
              _dateFormat.format(submission.submittedAt) +
                  (submission.wasRevised
                      ? ' · revised ${_dateFormat.format(submission.updatedAt!)}'
                      : ''),
              style: theme.textTheme.bodySmall,
            ),
            if (submission.answer.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(submission.answer),
            ],
            if (submission.answers.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < submission.answers.length; i++)
                Text('${i + 1}. ${submission.answers[i]}',
                    style: theme.textTheme.bodySmall),
            ],
            if (submission.hasAttachment)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(submission.attachmentName ?? 'Attached file'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => openAttachment(
                  context,
                  url: submission.attachmentUrl!,
                  fileName: submission.attachmentName,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: submission.isGraded
                      ? Text(
                          submission.wasGradedByTeacher
                              ? 'Marked ${_trim(submission.score!)} by ${submission.gradedByName ?? 'you'}'
                              : 'Auto-marked ${_trim(submission.autoScore!)}'
                                  '${submission.correctCount != null ? ' · ${submission.correctCount}/${item.questionCount} correct' : ''}',
                          style: theme.textTheme.bodySmall,
                        )
                      : Text('Not marked yet', style: theme.textTheme.bodySmall),
                ),
                TextButton.icon(
                  onPressed: onGrade,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(submission.wasGradedByTeacher ? 'Change mark' : 'Mark'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _trim(double value) =>
    value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
