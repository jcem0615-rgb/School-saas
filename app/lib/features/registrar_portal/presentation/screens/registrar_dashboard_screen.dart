import 'package:flutter/material.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';
import '../../../school_totals/presentation/widgets/school_totals_card.dart';
import 'package:go_router/go_router.dart';
import '../../../data_protection/presentation/screens/data_requests_screen.dart';

import '../../../payments/presentation/screens/payment_review_screen.dart';
import '../../../admissions/presentation/screens/admissions_screen.dart';
import '../../../faculty_portal/presentation/screens/grading_scheme_screen.dart';
import 'year_end_rollover_screen.dart';
import '../../../payments/presentation/screens/payment_settings_screen.dart';
import 'student_list_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

/// Landing screen for the Registrar/Cashier role. Student Registration
/// and Student Records/History are new this module. Payment Collection,
/// Receipts, and Balances reuse the screens built in the Payments module
/// directly from Student Detail -- no separate "Payments" entry point is
/// needed here since payments are always keyed by student. TOR, Form 137,
/// and printable Student IDs require PDF generation and are deferred to
/// the Documents module.
class RegistrarDashboardScreen extends StatelessWidget {
  const RegistrarDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Dashboard'),
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
            const SchoolTotalsCard(),
            const SizedBox(height: 20),
            Text('Manage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // First tile on the registrar's dashboard. The families
                // in here are not students yet, and the ones nobody
                // rings back stop being prospects within a fortnight --
                // so the pipeline is the thing to open in the morning,
                // not the roster, which will still be there at four.
                GlassTile(
                  icon: Icons.groups_outlined,
                  label: 'Admissions',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AdmissionsScreen())),
                ),
                GlassTile(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Student Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StudentListScreen())),
                ),
                // The registrar is the office a family actually walks up
                // to, so the queue belongs on their dashboard as much as
                // on the Director's.
                GlassTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Data Requests',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DataRequestsScreen())),
                ),
                GlassTile(
                  icon: Icons.fact_check_outlined,
                  label: 'Online Payments',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PaymentReviewScreen())),
                ),
                GlassTile(
                  icon: Icons.qr_code_2,
                  label: 'Payment Setup',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PaymentSettingsScreen())),
                ),
                // Run once a year, and the one operation here with no
                // undo. On the dashboard rather than buried in a menu
                // because a registrar looking for it in June should not
                // have to hunt, and because a screen nobody can find is
                // a school year rolled over in a spreadsheet instead.
                GlassTile(
                  icon: Icons.upgrade_outlined,
                  label: 'Year-End Rollover',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const YearEndRolloverScreen())),
                ),
                // The registrar signs the report cards, so the scheme
                // they are computed from is reachable from here too.
                GlassTile(
                  icon: Icons.rule_outlined,
                  label: 'Grading Scheme',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const GradingSchemeScreen())),
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
