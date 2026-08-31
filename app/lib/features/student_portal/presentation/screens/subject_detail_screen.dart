import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../faculty_portal/domain/entities/quarterly_grade.dart';
import '../../../faculty_portal/presentation/controllers/faculty_controller.dart'
    show gradingSchemeProvider;
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

    // The real quarterly grade, one per term, computed the way the school
    // says grades are computed.
    //
    // This used to be a flat average of every mark in the subject, with a
    // comment saying it was deliberately not called a final grade because
    // weighting was a school policy decision the app did not model. It
    // models it now, so the number here is the number that goes on the
    // report card -- and a student comparing the two should find them the
    // same, which is the whole point of not having two ways to compute a
    // grade.
    final scheme = ref.watch(gradingSchemeProvider).valueOrNull;
    final terms = {for (final g in grades) g.term}.toList()..sort();
    final byTerm = scheme == null
        ? const <QuarterlyGrade>[]
        : [
            for (final term in terms)
              computeQuarterlyGrade(
                subject: subject,
                term: term,
                grades: grades.where((g) => g.term == term),
                scheme: scheme,
              ),
          ];
    final graded = byTerm.where((g) => g.hasWork).toList();
    final latest = graded.isEmpty ? null : graded.last;

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
                  if (latest != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${latest.finalGrade}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${latest.term} · ${gradeDescriptor(latest.finalGrade)}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                    // Said plainly rather than left to be discovered. A
                    // grade computed from two of three components will
                    // move when the exam is marked, and a student who
                    // does not know that reads a provisional number as a
                    // final one.
                    if (latest.missingComponents.isNotEmpty)
                      Text(
                        'Still to come: '
                        '${latest.missingComponents.map((c) => c.displayLabel).join(' and ')}',
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
          if (graded.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('How this was worked out', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            // A grade a student cannot trace is one they have to take on
            // trust. The weights are not the same for every subject --
            // which is exactly the thing people assume -- so the group
            // that produced them is named.
            Text(
              graded.last.weights.label,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final quarter in graded)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(quarter.term, style: theme.textTheme.titleSmall),
                          Text(
                            '${quarter.finalGrade}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isPassing(quarter.finalGrade)
                                  ? null
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (final component in quarter.components)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            component.hasWork
                                ? '${component.component.displayLabel}: '
                                    '${component.raw.toStringAsFixed(0)} of '
                                    '${component.possible.toStringAsFixed(0)} '
                                    '(${component.percentageScore.toStringAsFixed(1)}%) '
                                    'at ${component.weight.toStringAsFixed(0)}%'
                                : '${component.component.displayLabel}: nothing recorded yet',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
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
                  title: Text('${g.term} · ${g.component.displayLabel}'),
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
