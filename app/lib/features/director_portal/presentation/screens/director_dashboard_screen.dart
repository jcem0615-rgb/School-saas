import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../emergency/presentation/screens/emergency_contacts_screen.dart';
import '../../../owner_portal/presentation/widgets/revenue_card.dart';
import '../../../payments/presentation/screens/fee_structures_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../schedules/presentation/screens/schedule_screen.dart';
import '../../../audit_trail/presentation/screens/audit_trail_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../controllers/director_controller.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'expenses_screen.dart';
import 'meetings_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _percentFormat = NumberFormat.percentPattern();

/// Landing screen for the Director role. Surfaces the numbers a Director
/// checks every morning (today's attendance rate, today's collections,
/// what's waiting on their decision) plus quick links into the four
/// CRUD screens this module owns.
class DirectorDashboardScreen extends ConsumerWidget {
  const DirectorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Director Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today at a glance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              summaryAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Text('Failed to load dashboard: $err'),
                data: (summary) => LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 560 ? 2 : 1);
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    // A fixed height, not an aspect ratio. At four columns
                    // 1.6 gave a sensible tile; at one column -- which is
                    // what a phone gets -- it made each stat 220pt tall for
                    // one number and a label, so the four of them filled
                    // the screen twice over before anything else appeared.
                    // The content does not grow with the width, so the
                    // height should not either. 164 is what the contents
                    // actually need -- 20+20 padding, a 44 icon, the gap,
                    // and two lines of label for the longest one -- so the
                    // card's own FittedBox never has to shrink the number
                    // to fit, which is what a tighter guess did.
                    mainAxisExtent: 164,
                    children: [
                      RevenueCard(
                        label: 'Attendance Rate Today',
                        value: summary.todayAttendanceTotalCount == 0
                            ? 'No records yet'
                            : _percentFormat.format(summary.todayAttendanceRate),
                        icon: Icons.fact_check_outlined,
                      ),
                      RevenueCard(
                        label: "Today's Collections",
                        value: _currencyFormat.format(summary.todayPaymentsTotal),
                        icon: Icons.payments_outlined,
                      ),
                      RevenueCard(
                        label: 'Pending Approvals',
                        value: '${summary.pendingApprovalsCount}',
                        icon: Icons.rule_folder_outlined,
                        accentColor: summary.pendingApprovalsCount > 0 ? Colors.orange : null,
                      ),
                      RevenueCard(
                        label: 'Upcoming Meetings',
                        value: '${summary.upcomingMeetingsCount}',
                        icon: Icons.event_outlined,
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 32),
              Text('Manage', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
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
                  GlassTile(
                    icon: Icons.calendar_view_week_outlined,
                    label: 'Class Schedule',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                  ),
                  GlassTile(
                    icon: Icons.insights_outlined,
                    label: 'Reports',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ReportsScreen())),
                  ),
                  // Next to Expenses on purpose: one is what the school
                  // spends, the other is what it charges, and a Director
                  // setting next year's budget is looking at both.
                  GlassTile(
                    icon: Icons.request_quote_outlined,
                    label: 'Fee Schedules',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const FeeStructuresScreen())),
                  ),
                  GlassTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Expenses',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ExpensesScreen())),
                  ),
                  // School-wide history. Every edit and soft delete made
                  // anywhere in the portal lands here via the audit
                  // trigger, which is what makes those actions reversible
                  // in practice -- you can see what changed and who did it.
                  // Editing the school's emergency numbers was always
                  // permitted for this role, but reachable only through
                  // Profile -- where somebody looks for their own
                  // settings, not for a list the whole school depends on.
                  GlassTile(
                    icon: Icons.local_phone_outlined,
                    label: 'Emergency Numbers',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
                  ),
                  GlassTile(
                    icon: Icons.history,
                    label: 'Audit Trail',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const AuditTrailScreen())),
                  ),
                  GlassTile(
                    icon: Icons.person_outline,
                    label: 'My Activity',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
