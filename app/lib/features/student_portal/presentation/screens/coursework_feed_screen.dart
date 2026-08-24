import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../controllers/student_controller.dart';
import 'coursework_detail_screen.dart';

final _dateFormat = DateFormat.yMMMd();

class CourseworkFeedScreen extends ConsumerStatefulWidget {
  final String section;
  const CourseworkFeedScreen({super.key, required this.section});

  @override
  ConsumerState<CourseworkFeedScreen> createState() => _CourseworkFeedScreenState();
}

class _CourseworkFeedScreenState extends ConsumerState<CourseworkFeedScreen> {
  CourseworkType? _filter;

  @override
  Widget build(BuildContext context) {
    final itemsAsync =
        ref.watch(myCourseworkProvider(CourseworkQuery(section: widget.section, typeFilter: _filter)));

    return Scaffold(
      appBar: AppBar(title: const Text('Assignments & Exams')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  ...CourseworkType.values.map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.displayLabel),
                          selected: _filter == t,
                          onSelected: (_) => setState(() => _filter = t),
                        ),
                      )),
                ],
              ),
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load coursework: $err')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('Nothing here yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final overdue = item.dueDate != null && item.dueDate!.isBefore(DateTime.now());
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: Text(
                          '${item.type.displayLabel} · ${item.subject} · ${item.teacherName}'
                          '${item.dueDate != null ? '\nDue ${_dateFormat.format(item.dueDate!)}' : ''}',
                        ),
                        isThreeLine: item.dueDate != null,
                        trailing: overdue
                            ? const Icon(Icons.warning_amber_outlined, color: Colors.red)
                            : (item.totalPoints != null ? Text('${item.totalPoints!.toStringAsFixed(0)} pts') : null),
                        // The row cannot show the description or the
                        // attachment, which are the parts a student needs
                        // in order to actually do the work.
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CourseworkDetailScreen(item: item),
                          ),
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
}
