import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controllers/student_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class MyGradesScreen extends ConsumerWidget {
  final String studentId;
  const MyGradesScreen({super.key, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesAsync = ref.watch(myGradesProvider(studentId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Grades')),
      body: gradesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load grades: $err')),
        data: (grades) {
          if (grades.isEmpty) {
            return const Center(child: Text('No grades submitted yet.'));
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
                  title: Text(g.subject),
                  subtitle: Text('${g.term} · ${_dateFormat.format(g.submittedAt)}'),
                  trailing: Text(
                    '${g.score.toStringAsFixed(1)}/${g.maxScore.toStringAsFixed(1)} (${g.percentage.toStringAsFixed(0)}%)',
                    style: Theme.of(context).textTheme.titleSmall,
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
