import '../../../emergency/presentation/screens/emergency_alerts_screen.dart';
import 'package:flutter/material.dart';

import 'guidance_records_screen.dart';
import 'summons_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

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
                GlassTile(
                  icon: Icons.emergency_share,
                  label: 'Emergency Alerts',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EmergencyAlertsScreen())),
                ),
                GlassTile(
                  icon: Icons.folder_shared_outlined,
                  label: 'Guidance Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const GuidanceRecordsScreen())),
                ),
                GlassTile(
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
