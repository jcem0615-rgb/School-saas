import '../../../emergency/presentation/screens/emergency_alerts_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../audit_trail/presentation/screens/audit_trail_screen.dart';
import '../../../director_portal/presentation/screens/announcements_screen.dart';
import 'branding_screen.dart';
import 'employee_list_screen.dart';
import 'programs_screen.dart';
import 'teacher_assignments_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

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
                GlassTile(
                  icon: Icons.badge_outlined,
                  label: 'Employee Management',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const EmployeeListScreen())),
                ),
                GlassTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Teacher Assignment',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const TeacherAssignmentsScreen())),
                ),
                GlassTile(
                  icon: Icons.school_outlined,
                  label: 'Strands & Programs',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ProgramsScreen())),
                ),
                GlassTile(
                  icon: Icons.emergency_share,
                  label: 'Emergency Alerts',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EmergencyAlertsScreen())),
                ),
                GlassTile(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                ),
                GlassTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan Attendance',
                  onTap: () => context.push('/scan-attendance'),
                ),
                GlassTile(
                  icon: Icons.history_outlined,
                  label: 'Audit Trail',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AuditTrailScreen())),
                ),

                GlassTile(

                  icon: Icons.palette_outlined,

                  label: 'School Branding',

                  onTap: () => Navigator.of(context)

                      .push(MaterialPageRoute(builder: (_) => const BrandingScreen())),

                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
