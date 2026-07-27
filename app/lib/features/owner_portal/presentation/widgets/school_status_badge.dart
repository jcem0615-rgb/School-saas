import 'package:flutter/material.dart';

import '../../domain/entities/school_summary.dart';

class SchoolStatusBadge extends StatelessWidget {
  final SchoolSubscriptionStatus status;

  const SchoolStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      SchoolSubscriptionStatus.active => (Colors.green.shade100, Colors.green.shade800),
      SchoolSubscriptionStatus.gracePeriod => (Colors.orange.shade100, Colors.orange.shade800),
      SchoolSubscriptionStatus.suspended => (Colors.red.shade100, Colors.red.shade800),
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
