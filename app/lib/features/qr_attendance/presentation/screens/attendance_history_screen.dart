import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/attendance_record.dart';
import '../controllers/qr_attendance_controller.dart';
import '../widgets/attendance_status_badge.dart';

final _timeFormat = DateFormat.jm();
final _dateFormat = DateFormat.yMMMEd();

/// Shows one person's attendance log. Reused across roles by passing a
/// different [personId]: a Student/Faculty/Staff member views their own
/// (personId == their own uid), a Parent views a linked child's, and
/// staff-facing monitoring screens (Director/Admin, built alongside those
/// portals) pass whichever student/employee they're looking up.
class AttendanceHistoryScreen extends ConsumerWidget {
  final String personId;
  final String? title;

  const AttendanceHistoryScreen({super.key, required this.personId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(attendanceHistoryStreamProvider(personId));

    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Attendance History')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load attendance: $err')),
        data: (records) {
          if (records.isEmpty) {
            return const Center(child: Text('No attendance records yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = records[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  title: Text(_dateFormat.format(DateTime.parse(r.date))),
                  subtitle: Text(_subtitleFor(r)),
                  trailing: AttendanceStatusBadge(status: r.status),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _subtitleFor(AttendanceRecord r) {
    final inTime = _timeFormat.format(r.timestampIn);
    if (r.timestampOut == null) return 'Time in: $inTime';
    return 'Time in: $inTime · Time out: ${_timeFormat.format(r.timestampOut!)}';
  }
}
