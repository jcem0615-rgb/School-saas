import 'package:flutter/material.dart';

import '../../../admin_portal/presentation/screens/teacher_assignments_screen.dart';
import '../../../director_portal/presentation/screens/announcements_screen.dart';
import '../../../director_portal/presentation/screens/approvals_screen.dart';
import '../../../director_portal/presentation/screens/meetings_screen.dart';
import '../../../registrar_portal/presentation/screens/student_list_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';

/// Landing screen for the Principal role -- a division-level academic
/// leader (e.g. "Elementary Principal," "High School Principal," "College
/// Dean"), distinct from Director (school-wide) in that a Principal's
/// visibility is meant to stay within their own division.
///
/// No new screens or backend logic here: every quick link below reuses a
/// screen already built for Director/Admin/Registrar Portal. What makes
/// a Principal's view actually different is firestore.rules -- if their
/// account has `employeeInfo.assignedDivision` set (Admin Portal ->
/// Employee Detail), the same division-scoping introduced in
/// docs/15-divisions-and-programs.md for Registrar/Faculty/Guidance
/// applies to Principal too. Left unset, a Principal sees school-wide,
/// same as before this role existed.
class PrincipalDashboardScreen extends StatelessWidget {
  const PrincipalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Principal Dashboard'),
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
                  icon: Icons.how_to_reg_outlined,
                  label: 'Student Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StudentListScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Teacher Assignment',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const TeacherAssignmentsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.event_available_outlined,
                  label: 'Meeting Scheduler',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MeetingsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.rule_folder_outlined,
                  label: 'Approvals',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ApprovalsScreen())),
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
