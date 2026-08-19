import 'package:flutter/material.dart';

import '../../domain/entities/attendance_record.dart';

class AttendanceStatusBadge extends StatelessWidget {
  final AttendanceStatus status;
  const AttendanceStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      AttendanceStatus.present => (Colors.green.shade100, Colors.green.shade800),
      AttendanceStatus.late => (Colors.orange.shade100, Colors.orange.shade800),
      AttendanceStatus.absent => (Colors.red.shade100, Colors.red.shade800),
      AttendanceStatus.excused => (Colors.blueGrey.shade100, Colors.blueGrey.shade800),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.displayLabel,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
