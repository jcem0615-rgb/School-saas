import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../controllers/student_controller.dart';
import 'coursework_detail_screen.dart';

final _dateFormat = DateFormat.yMMMd();

/// Everything a student has for one subject: the work set for it, and the
/// marks they have been given in it.
///
/// The two live together because they are the same question from the
/// student's side -- "how am I doing in Math?" is answered by the
/// coursework list and the grade list together, not by either alone.
class SubjectDetailScreen extends ConsumerWidget {
  final String subject;
  final String section;
  final String teacherName;
  final String studentId;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.section,
    required this.teacherName,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final courseworkAsync = ref.watch(myCourseworkProvider(CourseworkQuery(section: section)));
    final gradesAsync = ref.watch(myGradesProvider(studentId));

    final coursework = (courseworkAsync.valueOrNull ?? const <CourseworkItem>[])
        .where((c) => c.subject == subject)
        .toList();
    final grades = (gradesAsync.valueOrNull ?? const <Grade>[])
        .where((g) => g.subject == subject)
        .toList();

    // A simple average across every mark in the subject. Deliberately not
    // called a "final grade": weighting by term and by assessment type is
    // a school policy decision this module does not model.
    final average = grades.isEmpty
        ? null
        : grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length;

    return Scaffold(
      appBar: AppBar(title: Text(subject)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(teacherName,
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                  Text(section,
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                  if (average != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${average.toStringAsFixed(1)}% average',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'across ${grades.length} mark${grades.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Coursework', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (coursework.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing posted for this subject yet.'),
            )
          else
            ...coursework.map(
              (c) => Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(child: Text(c.type.displayLabel[0])),
                  title: Text(c.title),
                  subtitle: Text(
                    c.dueDate == null
                        ? c.type.displayLabel
                        : '${c.type.displayLabel} · Due ${_dateFormat.format(c.dueDate!)}',
                  ),
                  trailing: c.attachmentUrl != null
                      ? const Icon(Icons.attach_file, size: 18)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CourseworkDetailScreen(item: c)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('My Marks', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (grades.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No marks recorded for this subject yet.'),
            )
          else
            ...grades.map(
              (g) => Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text(g.term),
                  subtitle: Text(
                    g.remarks?.trim().isNotEmpty == true
                        ? g.remarks!
                        : _dateFormat.format(g.submittedAt),
                  ),
                  trailing: Text(
                    '${g.score.toStringAsFixed(0)} / ${g.maxScore.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
