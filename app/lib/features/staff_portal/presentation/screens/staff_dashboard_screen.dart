import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../faculty_portal/presentation/screens/material_requests_screen.dart';
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
