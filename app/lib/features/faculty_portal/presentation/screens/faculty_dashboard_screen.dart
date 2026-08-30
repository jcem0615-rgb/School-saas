import '../../../class_sessions/presentation/screens/todays_classes_screen.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';
import '../../../emergency/presentation/screens/emergency_alerts_screen.dart';
import '../../../schedules/presentation/screens/my_timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;

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
          const NotificationBell(),
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
            Text('Manage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // The one tile here that needs to know who is signed in:
                // a teacher's timetable is their own uid's, and this
                // dashboard is otherwise stateless.
                Consumer(
                  builder: (context, ref, _) => GlassTile(
                    icon: Icons.calendar_view_week_outlined,
                    label: 'My Schedule',
                    onTap: () {
                      final uid = ref.read(authStateProvider).valueOrNull?.uid;
                      if (uid == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MyTimetableScreen(
                            title: 'My Schedule',
                            teacherId: uid,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // First of the ordinary tiles, because it is the one
                // pressed at the start of every lesson.
                GlassTile(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Class Attendance',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TodaysClassesScreen())),
                ),
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
                GlassTile(
                icon: Icons.forum_outlined,
                label: 'Messages',
                onTap: () => context.push('/messages'),
                ),
                GlassTile(
                  icon: Icons.event_busy_outlined,
                  label: 'My Leave',
                  onTap: () => context.push('/my-leave'),
                ),
                GlassTile(
                  icon: Icons.punch_clock_outlined,
                  label: 'My Timesheet',
                  onTap: () => context.push('/my-timesheet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
