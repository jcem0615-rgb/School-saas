import '../../../emergency/presentation/screens/emergency_alerts_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../director_portal/presentation/screens/announcements_screen.dart';
import 'coursework_list_screen.dart';
import 'grades_screen.dart';
import 'material_requests_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

/// Landing screen for the Faculty role. Coursework (Lesson Plans/Lessons/
/// Assignments/Projects/Exams/Quizzes), Grade Submission, and Material
/// Requests are new this module. Attendance reuses the QR scanner
/// (Faculty is in the scanner-allowed role list from Module 7);
/// Announcements links directly into the Director Portal screen Faculty
/// already has read access to.
class FacultyDashboardScreen extends StatelessWidget {
  const FacultyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Dashboard'),
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
                  icon: Icons.menu_book_outlined,
                  label: 'Coursework',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CourseworkListScreen())),
                ),
                GlassTile(
                  icon: Icons.grade_outlined,
                  label: 'Grade Submission',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GradesScreen())),
                ),
                GlassTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Material Requests',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MaterialRequestsScreen())),
                ),
                GlassTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan Attendance',
                  onTap: () => context.push('/scan-attendance'),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
