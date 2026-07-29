import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../audit_trail/presentation/screens/audit_trail_screen.dart';
import '../../../director_portal/presentation/screens/announcements_screen.dart';
import 'employee_list_screen.dart';
import 'programs_screen.dart';
import 'teacher_assignments_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';

/// Landing screen for the Admin role. Employee Management, User Approval
/// (via Employee detail's activate/suspend action), Reset Password (also
/// in Employee detail), and Teacher Assignment are new this module.
/// Announcements is a direct link into the screen already built for
/// Director Portal (rules already permit admin), and Attendance
/// Monitoring reuses AttendanceHistoryScreen from QR Attendance per
/// employee. Inventory, Schedules, and Monthly Reports are explicitly
/// deferred -- see docs/09-admin-portal.md.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My Activity',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickLinkTile(
                  icon: Icons.badge_outlined,
                  label: 'Employee Management',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const EmployeeListScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Teacher Assignment',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const TeacherAssignmentsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.school_outlined,
                  label: 'College Programs',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ProgramsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan Attendance',
                  onTap: () => context.push('/scan-attendance'),
                ),
                _QuickLinkTile(
                  icon: Icons.history_outlined,
                  label: 'Audit Trail',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AuditTrailScreen())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
