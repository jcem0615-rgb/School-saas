import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/student_controller.dart';
import 'subject_detail_screen.dart';

/// Not the full day/time/room Schedule grid (deferred -- see
/// docs/12-student-portal.md), but a real, useful "who teaches what"
/// view derived from Admin Portal's existing teacherAssignments data.
class MySubjectsScreen extends ConsumerWidget {
  final String section;
  /// Needed to show the student their own marks inside a subject.
  final String studentId;
  const MySubjectsScreen({super.key, required this.section, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(mySubjectsProvider(section));

    return Scaffold(
      appBar: AppBar(title: const Text('My Subjects')),
      body: subjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load subjects: $err')),
        data: (subjects) {
          if (subjects.isEmpty) {
            return const Center(child: Text('No subjects assigned yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = subjects[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(s.subject),
                  subtitle: Text(s.teacherName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubjectDetailScreen(
                        subject: s.subject,
                        section: section,
                        teacherName: s.teacherName,
                        studentId: studentId,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
