import '../../../emergency/presentation/screens/emergency_alerts_screen.dart';
import '../../../school_totals/presentation/widgets/school_totals_card.dart';
import 'package:go_router/go_router.dart';
import '../../../schedules/presentation/screens/schedule_screen.dart';
import '../../../emergency/presentation/screens/emergency_contacts_screen.dart';
import 'package:flutter/material.dart';

import '../../../admin_portal/presentation/screens/teacher_assignments_screen.dart';
import '../../../director_portal/presentation/screens/announcements_screen.dart';
import '../../../director_portal/presentation/screens/approvals_screen.dart';
import '../../../director_portal/presentation/screens/meetings_screen.dart';
import '../../../registrar_portal/presentation/screens/student_list_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

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
          // Profile was routed but nothing navigated to it, so the one
          // screen every role shares -- and the only way into the
          // privacy notice and data requests -- could not be opened at
          // all. A route with no door is a screen that does not exist.
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My Activity',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
          ),
        ],
      ),
      // Scrollable, not a bare Column. A dashboard is a grid of tiles
      // that grows every time a module lands, and a Column that has run
      // out of room does not scroll -- it overflows, which on a phone is
      // a black-and-yellow stripe across the bottom row of a school's
      // main screen.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SchoolTotalsCard(),
            const SizedBox(height: 20),
            Text('Manage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                GlassTile(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Student Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StudentListScreen())),
                ),
                // Next to Teacher Assignment: one says who teaches what,
                // the other says when. A principal covering an absent
                // teacher needs both open.
                GlassTile(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'Class Schedule',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                ),
                GlassTile(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Teacher Assignment',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const TeacherAssignmentsScreen())),
                ),
                GlassTile(
                  icon: Icons.emergency_share,
                  label: 'Emergency Alerts',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EmergencyAlertsScreen())),
                ),
                // The numbers themselves, not the alerts raised against
                // them. Editing them was always allowed here -- both
                // firestore.rules and the screen's own editor list this
                // role -- but the only way in was through Profile, which
                // is where somebody looks for their own settings, not for
                // a list the whole school depends on. A number that is
                // wrong because nobody could find the screen to fix it is
                // the same as no number at all.
                GlassTile(
                  icon: Icons.local_phone_outlined,
                  label: 'Emergency Numbers',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
                ),
                GlassTile(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                ),
                GlassTile(
                  icon: Icons.event_available_outlined,
                  label: 'Meeting Scheduler',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MeetingsScreen())),
                ),
                GlassTile(
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
