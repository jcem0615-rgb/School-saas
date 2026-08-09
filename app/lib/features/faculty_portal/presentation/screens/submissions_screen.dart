import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../../registrar_portal/presentation/controllers/registrar_controller.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/coursework_submission.dart';
import '../controllers/faculty_controller.dart';

final _dateFormat = DateFormat.yMMMd().add_jm();

/// What has been handed in for one piece of coursework.
///
/// Deliberately not a grading screen. Marks live in the Grades flow,
/// which already knows about terms and max scores; this answers the
/// question that comes first and has no home otherwise -- who has done
/// the work, and what did they write?
class SubmissionsScreen extends ConsumerWidget {
  final CourseworkItem item;
  const SubmissionsScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissionsAsync = ref.watch(submissionsForProvider(item.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submissions'),
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
                ...submissions.map((s) => _SubmissionCard(submission: s, item: item)),
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

class _Summary extends StatelessWidget {
  final int submitted;
  final int missing;
  final int late;

  const _Summary({required this.submitted, required this.missing, required this.late});

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
      ],
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final CourseworkSubmission submission;
  final CourseworkItem item;

  const _SubmissionCard({required this.submission, required this.item});

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
            if (submission.hasAttachment)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(submission.attachmentName ?? 'Attached file'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final uri = Uri.parse(submission.attachmentUrl!);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Could not open the file.')));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
