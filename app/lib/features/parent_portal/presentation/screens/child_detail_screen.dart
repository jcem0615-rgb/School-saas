import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../payments/presentation/screens/payment_history_screen.dart';
import '../../../qr_attendance/presentation/screens/attendance_history_screen.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../../student_portal/presentation/screens/my_grades_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Child Profile plus quick links -- Attendance Monitoring, Grades, and
/// Statement of Account/Payment Monitoring all reuse screens already
/// built for Student Portal and Payments. `allowRefunds: false` on the
/// payment history reuse is deliberate: a Parent monitors payments, but
/// refund authority stays with Director/Admin (see docs/08-payments.md).
class ChildDetailScreen extends StatelessWidget {
  final StudentSummary child;
  const ChildDetailScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(child.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: child.photoUrl != null ? NetworkImage(child.photoUrl!) : null,
                child: child.photoUrl == null ? const Icon(Icons.school_outlined, size: 32) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.fullName, style: Theme.of(context).textTheme.titleLarge),
                    Text('${child.studentNumber} · ${child.classLabel}'),
                    Text(child.status.displayLabel, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Balance', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                Text(
                  _currencyFormat.format(child.balance),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (child.guardianContacts.isNotEmpty) ...[
            Text('Guardian Contacts', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...child.guardianContacts.map((g) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.contact_phone_outlined),
                  title: Text(g.name),
                  subtitle: Text('${g.relationship} · ${g.phone}'),
                )),
            const Divider(height: 32),
          ],
          Text('Monitor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionChip(
                icon: Icons.fact_check_outlined,
                label: 'Attendance',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttendanceHistoryScreen(personId: child.id, title: '${child.fullName} - Attendance'),
                  ),
                ),
              ),
              _ActionChip(
                icon: Icons.grade_outlined,
                label: 'Grades',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => MyGradesScreen(studentId: child.id))),
              ),
              _ActionChip(
                icon: Icons.receipt_long_outlined,
                label: 'Statement of Account',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PaymentHistoryScreen(studentId: child.id, studentName: child.fullName, allowRefunds: false),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);
  }
}
