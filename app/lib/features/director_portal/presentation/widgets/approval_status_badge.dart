import 'package:flutter/material.dart';

import '../../domain/entities/approval_request.dart';

class ApprovalStatusBadge extends StatelessWidget {
  final ApprovalStatus status;
  const ApprovalStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      ApprovalStatus.pending => (Colors.orange.shade100, Colors.orange.shade800),
      ApprovalStatus.approved => (Colors.green.shade100, Colors.green.shade800),
      ApprovalStatus.rejected => (Colors.red.shade100, Colors.red.shade800),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.value.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
