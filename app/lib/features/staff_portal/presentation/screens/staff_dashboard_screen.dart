import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../faculty_portal/presentation/screens/material_requests_screen.dart';
import 'checklist_screen.dart';
import 'daily_reports_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';

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
                _QuickLinkTile(
                  icon: Icons.checklist_outlined,
                  label: 'Checklist',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChecklistScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.summarize_outlined,
                  label: 'Daily Reports',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DailyReportsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Material Requests',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MaterialRequestsScreen())),
                ),
                // Staff are scanned, not scanners -- an admin runs staff
                // timekeeping -- so what they need at hand is their own ID
                // to present, not a camera.
                _QuickLinkTile(
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
