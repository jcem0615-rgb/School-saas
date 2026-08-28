import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../domain/entities/schedule_block.dart';
import '../controllers/schedule_controller.dart';
import '../documents/timetable_pdf.dart';
import '../widgets/timetable_view.dart';

/// One week, read-only: a student's or a child's section, or a
/// teacher's own classes.
///
/// The same screen for all three because it is the same question. Who is
/// asking only changes which blocks it is handed, and that is decided by
/// the caller rather than sniffed from the role here.
class MyTimetableScreen extends ConsumerWidget {
  final String title;

  /// Exactly one of these. A section timetable shows the teacher of each
  /// class; a teacher's own shows which section they are in front of.
  final String? section;
  final String? teacherId;

  const MyTimetableScreen({
    super.key,
    required this.title,
    this.section,
    this.teacherId,
  }) : assert(section != null || teacherId != null,
            'A timetable is either a section\'s or a teacher\'s.');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider);
    final blocks = section != null
        ? ref.watch(sectionScheduleProvider(section!))
        : ref.watch(teacherScheduleProvider(teacherId!));
    final year = ref.watch(scheduleYearProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (blocks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print',
              onPressed: () => TimetablePdf.print(
                title: title,
                subtitle: 'School Year $year',
                blocks: blocks,
                branding: ref.read(brandingProvider).valueOrNull ?? SchoolBranding.empty,
                preparedByName:
                    ref.read(authStateProvider).valueOrNull?.fullName ?? 'the office',
              ),
            ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The timetable could not be loaded: $err'),
          ),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('School Year $year', style: Theme.of(context).textTheme.bodySmall),
            TimetableView(
              blocks: blocks,
              showSection: teacherId != null,
              showTeacher: section != null,
              // Monday's classes are not what somebody opens this on a
              // Thursday to find out.
              highlightDay: DateTime.now().weekday,
              emptyMessage: 'No classes are timetabled yet.\n\n'
                  'The school office sets the timetable; it will appear here '
                  'once they have.',
            ),
          ],
        ),
      ),
    );
  }
}

/// What is on next, for a dashboard.
///
/// Null outside school hours and on a day with nothing left, which is
/// the answer most of the time and is why this returns a nullable rather
/// than the next block on any day: "your next class is on Monday" shown
/// at four o'clock on a Friday is noise.
ScheduleBlock? nextClassToday(List<ScheduleBlock> blocks, {DateTime? now}) {
  final moment = now ?? DateTime.now();
  final minuteOfDay = moment.hour * 60 + moment.minute;
  final today = blocks.where((b) => b.dayOfWeek == moment.weekday).toList()
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  for (final block in today) {
    // A class already under way is the one somebody wants named, not the
    // one after it.
    if (block.endMinute > minuteOfDay) return block;
  }
  return null;
}
