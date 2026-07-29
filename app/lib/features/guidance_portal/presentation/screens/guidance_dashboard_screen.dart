import 'package:flutter/material.dart';

import 'guidance_records_screen.dart';
import 'summons_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';

/// Landing screen for the Guidance role. Student Guidance Records and
/// Student Summons are new this module. Reports is deferred to the
/// Reports module; Audit Trail reuses MyActivityScreen (linked from the
/// shared Profile screen, same as every other role).
class GuidanceDashboardScreen extends StatelessWidget {
  const GuidanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guidance Dashboard'),
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
                  icon: Icons.folder_shared_outlined,
                  label: 'Guidance Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const GuidanceRecordsScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.meeting_room_outlined,
                  label: 'Student Summons',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SummonsScreen())),
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
