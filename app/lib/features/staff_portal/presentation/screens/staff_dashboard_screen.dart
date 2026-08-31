import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../notifications/presentation/widgets/notification_bell.dart';
import '../../../faculty_portal/presentation/screens/material_requests_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import 'checklist_screen.dart';
import 'daily_reports_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

/// Landing screen for the Staff (maintenance) role. Checklist and Daily
/// Reports are new this module. Material Requests reuses the exact same
/// screen Faculty Portal built (both roles file into the same generic
/// approvals inbox); QR Attendance reuses the scanner (Staff has been in
/// the scanner-allowed role list since Module 7).
class StaffDashboardScreen extends StatelessWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
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
            Text('Today', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                GlassTile(
                  icon: Icons.checklist_outlined,
                  label: 'Checklist',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChecklistScreen())),
                ),
                GlassTile(
                  icon: Icons.summarize_outlined,
                  label: 'Daily Reports',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DailyReportsScreen())),
                ),
                // The stock those requests draw down. Next to them on
                // purpose: the person deciding a material request is the
                // person who knows whether there is any left.
                GlassTile(
                  icon: Icons.warehouse_outlined,
                  label: 'Inventory',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const InventoryScreen())),
                ),
                GlassTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Material Requests',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MaterialRequestsScreen())),
                ),
                // Staff are scanned, not scanners -- an admin runs staff
                // timekeeping -- so what they need at hand is their own ID
                // to present, not a camera.
                GlassTile(
                  icon: Icons.badge_outlined,
                  label: 'My e-ID',
                  onTap: () => context.push('/qr-id'),
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
