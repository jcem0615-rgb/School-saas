import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../director_portal/presentation/screens/announcements_screen.dart';
import 'coursework_list_screen.dart';
import 'grades_screen.dart';
import 'material_requests_screen.dart';

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
      appBar: AppBar(title: const Text('Faculty Dashboard')),
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
                  icon: Icons.menu_book_outlined,
                  label: 'Coursework',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CourseworkListScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.grade_outlined,
                  label: 'Grade Submission',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GradesScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Material Requests',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MaterialRequestsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan Attendance',
                  onTap: () => context.push('/scan-attendance'),
                ),
                _QuickLinkTile(
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
