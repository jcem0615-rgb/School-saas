import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../director_portal/presentation/screens/announcements_screen.dart';
import '../../../emergency/presentation/screens/sos_screen.dart';
import '../../../payments/presentation/screens/payment_history_screen.dart';
import '../../../qr_attendance/presentation/screens/attendance_history_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../controllers/student_controller.dart';
import 'coursework_feed_screen.dart';
import 'my_grades_screen.dart';
import 'my_subjects_screen.dart';
import 'promissory_note_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(myStudentRecordProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My School'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My Activity',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
          ),
        ],
      ),
      body: recordAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load your record: $err')),
        data: (student) {
          if (student == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No student record is linked to this account yet. Please contact your school registrar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(student.fullName, style: Theme.of(context).textTheme.headlineSmall),
              Text('${student.studentNumber} · ${student.gradeLevel} - ${student.section}'),
              const SizedBox(height: 8),
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
                      _currencyFormat.format(student.balance),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickLinkTile(
                    icon: Icons.menu_book_outlined,
                    label: 'Subjects',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MySubjectsScreen(
                              section: student.section,
                              studentId: student.id,
                            ))),
                  ),
                  _QuickLinkTile(
                    icon: Icons.assignment_outlined,
                    label: 'Assignments & Exams',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => CourseworkFeedScreen(section: student.section))),
                  ),
                  _QuickLinkTile(
                    icon: Icons.grade_outlined,
                    label: 'Grades',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MyGradesScreen(studentId: student.id))),
                  ),
                  _QuickLinkTile(
                    icon: Icons.fact_check_outlined,
                    label: 'Attendance',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AttendanceHistoryScreen(personId: student.id, title: 'My Attendance'),
                      ),
                    ),
                  ),
                  _QuickLinkTile(
                    icon: Icons.payments_outlined,
                    label: 'Payments & Balance',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PaymentHistoryScreen(studentId: student.id)),
                    ),
                  ),
                  _QuickLinkTile(
                    icon: Icons.description_outlined,
                    label: 'Promissory Note',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const PromissoryNoteScreen())),
                  ),
                  _QuickLinkTile(
                    icon: Icons.emergency_share,
                    label: 'Emergency',
                    onTap: () {
                      final student = ref.read(myStudentRecordProvider).valueOrNull;
                      if (student == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SosScreen(student: student)),
                      );
                    },
                  ),
                  _QuickLinkTile(
                    icon: Icons.campaign_outlined,
                    label: 'Announcements',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                  ),
                  _QuickLinkTile(
                    icon: Icons.qr_code,
                    label: 'My QR ID',
                    onTap: () => context.push('/qr-id'),
                  ),
                ],
              ),
            ],
          );
        },
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
