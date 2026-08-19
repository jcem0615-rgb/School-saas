import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      appBar: AppBar(title: const Text('Grade Submission')),
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
                  child: TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sectionController,
                    decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
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
            child: gradesAsync == null
                ? const Center(child: Text('Enter a subject and section, then tap Load.'))
                : gradesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Failed to load grades: $err')),
                    data: (grades) {
                      if (grades.isEmpty) {
                        return const Center(child: Text('No grades submitted for this subject/section yet.'));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: grades.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final g = grades[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: ListTile(
                              title: Text(g.studentName),
                              subtitle: Text('${g.term} · ${_dateFormat.format(g.submittedAt)}'),
                              trailing: Text(
                                '${g.score.toStringAsFixed(1)} / ${g.maxScore.toStringAsFixed(1)}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
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

  Future<void> _showSubmitDialog(BuildContext context, WidgetRef ref, GradeQuery query) async {
    final studentIdController = TextEditingController();
    final studentNameController = TextEditingController();
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
                decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: studentNameController,
                decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: termController,
                decoration: const InputDecoration(labelText: 'Term (e.g. Q1)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Score', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Score', border: OutlineInputBorder()),
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
